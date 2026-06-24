# HTC-Grid EC2 Worker Bootstrap Sequence

What happens from the moment ORB launches an EC2 worker until it is processing tasks. This is
the `worker_backend = "ec2"` instance lifecycle: ORB `RunInstances` from the worker profile →
AL2023 cloud-init runs the rendered user-data → Docker + the N agent/RIE pairs come up → each
agent long-polls the shared control plane. It is the EC2 analogue of a pod scheduled onto an
EKS node by KEDA + Cluster Autoscaler.

The launch is driven by the scaling loop in
[`ec2-scaling-up-sequence.md`](ec2-scaling-up-sequence.md); this doc zooms into a single instance.
Everything below is grounded in `compute_plane_ec2/user-data.sh.tftpl` and
`compute_plane_ec2/launch_template.tf`.

## High-level (instance comes alive)

```mermaid
sequenceDiagram
    autonumber
    box rgb(255,243,224) ORB
        participant ORB as orb_orchestrator<br/>Lambda
    end
    box rgb(252,228,236) Worker instance (AL2023)
        participant EC2 as EC2 instance
        participant CI as cloud-init (user-data)
        participant CMP as Docker compose<br/>(N pairs)
    end
    box rgb(232,245,233) Control plane (shared)
        participant Q as SQS + DynamoDB + Redis
    end

    ORB->>EC2: RunInstances (worker template: AL2023 AMI,<br/>instance profile, SG, IMDSv2 hop=3, gp3, user_data)
    EC2->>CI: boot, run user-data as root
    CI->>CI: IMDSv2 token, INSTANCE_ID; compute NUM_PAIRS
    CI->>CMP: docker compose up -d (getlayer, rie, agent per pair)
    CMP->>Q: each agent long-polls for tasks
    Note over CMP,Q: instance is now processing work
```

## Detailed (ordered user-data steps)

```mermaid
sequenceDiagram
    autonumber
    box rgb(252,228,236) Worker instance (AL2023)
        participant CI as cloud-init (user-data)
        participant IMDS as IMDSv2
        participant OS as dnf / systemd
        participant PAIR as N x getlayer/rie/agent
    end
    box rgb(225,245,254) AWS services
        participant S3 as S3
        participant SSM as SSM Parameter Store
        participant ECR as ECR
        participant CW as CloudWatch Logs
    end

    Note over CI: set -euxo pipefail; tee to /var/log/htc-bootstrap.log

    CI->>IMDS: PUT token (TTL 600), GET instance-id
    Note over CI: NUM_PAIRS = override if set, else<br/>min(floor(vCPU per PAIR_CPU), floor(memMB per PAIR_MEMORY)), min 1
    CI->>OS: dnf install -y docker; systemctl enable --now docker
    CI->>S3: aws s3 cp COMPOSE_S3 to /usr/libexec/docker/cli-plugins/docker-compose
    Note over CI: github/pypi unreachable on private subnets:<br/>compose plugin staged via S3, not curled
    CI->>CI: mkdir /opt/htc agent-config, compose, and task-i per pair (chmod 777)
    CI->>SSM: get-parameter agent_config --with-decryption to Agent_config.tfvars.json
    CI->>ECR: aws ecr get-login-password into docker login
    CI->>CI: write /opt/htc/compose/.env (ECR, images, REGION, FUNCTION, HANDLER, S3_SOURCE, INSTANCE_ID)
    CI->>CI: render docker-compose.yml: a getlayer-i / rie-i / agent-i triplet per pair

    CI->>PAIR: docker compose -p htc-workers up -d
    loop per pair i in 0..NUM_PAIRS-1
        PAIR->>S3: getlayer-i: download-layer.sh to /var/task (runs once, exits 0)
        PAIR->>ECR: rie-i: start aws-lambda-rie on :8080 (after getlayer success)
        PAIR->>ECR: agent-i: start (network_mode + pid = service:rie-i)
    end
    PAIR-->>CW: every container stdout/stderr to awslogs<br/>stream INSTANCE_ID-pair-i (getlayer, rie, agent)
    Note over CI: echo "bootstrap complete: NUM_PAIRS pairs"
```

## What ORB launches (the worker template)

| Attribute | Value (`launch_template.tf`) |
|-----------|------------------------------|
| AMI | latest AL2023 (`data.aws_ssm_parameter.al2023_ami`) |
| Instance type | `var.instance_type` (default `m6i.large`) |
| IAM instance profile | `aws_iam_instance_profile.worker` (ECR pull, S3, SSM, CloudWatch Logs) |
| Security group | `aws_security_group.worker` - no inbound; egress only |
| Metadata | IMDSv2 required, `http_put_response_hop_limit = 3` (containers reach IMDS) |
| Root volume | gp3, `var.instance_volume_size` |
| User data | rendered `user-data.sh.tftpl` |

## What gets installed / created on the instance

- **Packages:** `docker`; the compose CLI plugin staged from S3 (not from GitHub - private subnets have no egress to it).
- **Dirs:** `/opt/htc/agent-config`, `/opt/htc/compose`, and one `/opt/htc/task-i` per pair (chmod 777 - getlayer/RIE run as uid 99 and must write `/var/task`).
- **Config:** `Agent_config.tfvars.json` pulled from SSM SecureString; `.env` + `docker-compose.yml` rendered for `NUM_PAIRS`.
- **Log file:** `/var/log/htc-bootstrap.log` (all user-data stdout/stderr via `tee`).

## How containers launch (the per-pair triplet)

Each pair is three services with strict ordering:

```
getlayer-i  --(service_completed_successfully)-->  rie-i  --(service_started)-->  agent-i
 download         exits 0 once /var/task             aws-lambda-rie :8080         shares rie-i's
 lambda code      is populated                       (RIE_IMAGE)                  network + pid ns
```

- **getlayer-i** runs `download-layer.sh` once into `/opt/htc/task-i:/var/task`, then exits 0. `rie-i` waits on `service_completed_successfully`.
- **rie-i** runs the Lambda Runtime Interface Emulator on `:8080` with the handler; `cpus`/`mem_limit` per the pair budget; `stop_grace_period: 1500s`.
- **agent-i** joins rie-i with `network_mode: service:rie-i` and `pid: service:rie-i`, so it reaches the RIE at `http://localhost:8080` and shares its process namespace. Identity is `MY_POD_NAME = INSTANCE_ID-pair-i`. It long-polls the shared control plane for tasks.

## Notes

- **Auto `NUM_PAIRS`.** Override via `pairs_per_instance`; otherwise `min(floor(vCPU/PAIR_CPU), floor(memMB/PAIR_MEMORY))`, floored at 1, so each instance packs as many pairs as its size allows.
- **No inbound; SSM-only.** The worker SG has no ingress; all control (including cordon `docker compose stop`, ADR-003) arrives via SSM RunShellScript.
- **Ordering guarantees.** compose `depends_on` conditions make the layer land before the RIE starts and the RIE start before the agent - no race on `/var/task` or the local endpoint.
- **Logs.** Every container streams to CloudWatch under `INSTANCE_ID-pair-i-{getlayer,rie,agent}`, so a single instance's pairs are individually traceable.
- **Graceful drain tie-in.** `stop_grace_period: 1500s` and the RIE `AWS_LAMBDA_GRACEFUL_TERMINATION_DELAY` give an in-flight task time to finish when the controller cordons the instance (see [`ec2-scaling-down-sequence.md`](ec2-scaling-down-sequence.md)).
- **Live-verify.** `cat /var/log/htc-bootstrap.log` (expect `bootstrap complete`); `docker compose -p htc-workers ps` (expect getlayer Exited 0, rie + agent Up per pair).
