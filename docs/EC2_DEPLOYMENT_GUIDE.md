# HTC-Grid EC2 Backend - Deployment Guide

How to deploy the **EC2/ORB worker backend** (no EKS): workers run as Docker-Compose
Agent+RIE pairs on plain EC2 instances, scaled by an ORB orchestrator Lambda and a
queue-driven capacity controller. The control plane (SQS, DynamoDB, Redis, S3,
Cognito, API Gateway) is shared with the EKS backend.

For architecture/internals see [`EC2_BACKEND_ARCHITECTURE.md`](./EC2_BACKEND_ARCHITECTURE.md); for
common questions (scale-down, busy detection, drain deadlines, failure modes) see
[`EC2_BACKEND_FAQ.md`](./EC2_BACKEND_FAQ.md).

---

## 1. Prerequisites

- Tools: `terraform` (1.5.4), `aws` (v2), `docker`, `make`, `jq`, `python3` + an
  activated repo virtualenv, valid AWS credentials (`aws sts get-caller-identity`).
- `export TAG=<project>` (S3-naming-safe: lowercase, digits, hyphens) and
  `export REGION=<region>` (e.g. `eu-west-1`).

---

## 2. One-command deploy (recommended)

```bash
./scripts/deploy-htc-eks.sh --backend ec2 --tag "$TAG" --region "$AWS_REGION"
```

The script runs every step below in order, with logging to `logs/`. It is idempotent
(safe to re-run). Add `--reset` if you changed `--tag`/`--region` since the last run
on this checkout.

> **One caveat:** the script builds the project images but assumes the shared RIE base
> image `lambda:provided` already exists in the region. If you are deploying in a
> **brand-new region/account** (one that has never run HTC-Grid), first run the
> runtime build once - see step 3, item C. Otherwise skip it.

After it finishes, deploy-only validation prints the agent-config path, the worker
CloudWatch log group, and the task-submission command. Jump to **§5**.

---

## 3. Manual deploy (what the script does)

```bash
# 1. State storage - 3 S3 buckets + KMS (shared with EKS; skip if the stack exists)
make init-grid-state TAG=$TAG REGION=$AWS_REGION

# 2. Build the worker images + workload, then generate the EC2 config (config LAST)
make ecr-login REGION=$AWS_REGION
make all TAG=$TAG REGION=$AWS_REGION                 # builds awshpc-lambda:<tag>, lambda-init:<tag> (+ lambda.zip), submitter
make -C examples/submissions/k8s_jobs build push TAG=$TAG REGION=$AWS_REGION
make -C examples/workloads/c++/mock_computation upload TAG=$TAG REGION=$AWS_REGION ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
make config-ec2 TAG=$TAG REGION=$AWS_REGION          # writes generated/grid_config.json with "worker_backend":"ec2"

# 3. Deploy (terraform also zip-builds the ORB orchestrator + capacity controller)
make init-grid-deployment TAG=$TAG REGION=$AWS_REGION
make auto-apply-custom-runtime TAG=$TAG REGION=$AWS_REGION
```

**C. Fresh region only - build the RIE base image `lambda:provided`** (once per
region; it is account/region-global and tag-independent). Run **before** step 3 above:

```bash
make init-images TAG=$TAG REGION=$AWS_REGION
make transfer-images TAG=$TAG REGION=$AWS_REGION
```

Check whether it already exists first:
`aws ecr describe-images --repository-name lambda --image-ids imageTag=provided --region $AWS_REGION`

> **Do NOT use `make happy-path` for EC2.** It runs `config-c++` (the EKS config) and
> would overwrite your EC2 config. Always run `config-ec2` last.

---

## 4. What gets created

| Component | Notes |
|---|---|
| VPC + control plane | Shared with EKS, unchanged |
| `compute_plane_ec2` | Worker IAM role, SG, log group, AMI lookup, cloud-init (Agent+RIE pairs); ORB builds its own launch template per fleet request |
| `orb_orchestrator` | Zip Lambda - launches/terminates EC2 workers (built by terraform) |
| `capacity_controller` | Zip Lambda on a 1-min timer - scales the fleet from queue backlog |
| SSM SecureString | Agent config pulled by workers at boot |

**Not created:** no EKS cluster, no node groups, no kubeconfig, no kubectl, no
Grafana/InfluxDB. `node_drainer` and `scaling_metrics` are gated off
(`enable_node_drainer` / `enable_scaling_metrics = worker_backend == "eks"`) - the EC2
controller reads the SQS backlog directly, so it does not need the `pending_tasks_ddb` publisher.

Worker images pulled at boot: `awshpc-lambda:<tag>`, `lambda-init:<tag>`,
`lambda:provided`; workload from `s3://<lambda-layer-bucket>/lambda.zip`.

---

## 5. Submit a test task & verify

No `kubectl`. Use the Python client:

```bash
export AGENT_CONFIG_FILE=$(cd deployment/grid/terraform && terraform output -raw agent_config)
python examples/client/python/simple_client.py
```

Expect `All results are verified!`. Workers are launched **on demand** by ORB when the
backlog grows - none run until there is work.

**Where to look:**
- Worker container logs: CloudWatch `/aws/ec2/<TAG>/worker-logs`
- Running workers: EC2 console (instances launched by ORB)
- Task state: DynamoDB `htc_tasks_state_table-<TAG>`
- Scaling: capacity controller Lambda logs (the `capacity reconcile` line shows `backlog`,
  read directly from the SQS task queue; `pending_tasks_ddb` is EKS-only)

---

## 6. Scaling knobs

Defaults come from `examples/configurations/Makefile`; override by editing
`generated/grid_config.json` before apply (or pass `VAR=value` to `make config-ec2`):

| Key | Default | Meaning |
|---|---|---|
| `orb_template_id` | `EC2Fleet-Instant-OnDemand` | Which prebuilt ORB template to use (see `config/aws_templates.json`): `EC2Fleet-Instant-OnDemand` (enumerated types - the default), `EC2Fleet-Instant-Spot` (enumerated spot), `EC2Fleet-Instant-ABIS` (AWS picks any type in a vCPU/mem range - **currently unusable**: orb-py's validator rejects ABIS-only templates, see §8) |
| `ec2_worker_vcpus` | `1` | vCPUs per worker pair; sizes `NUM_PAIRS` at boot and converts pairs↔vCPUs in the controller |
| `ec2_worker_memory_mb` | `2048` | MiB per worker pair (the other half of the boot-time auto-pack) |
| `orb_target_pending_per_pair` | `4` | Backlog target per worker pair: `desired_pairs = ceil(backlog / this)` |
| `orb_min_vcpus` / `orb_max_vcpus` | `0` / `64` | Fleet bounds, in **total vCPUs** (floor/ceiling of the vCPU target) |
| `orb_max_instances` | `5` | ORB per-template instance-count cap (upper safety bound) |
| `orb_control_interval` | `60` | Controller reconcile interval (s) |

The capacity controller scales the fleet in **vCPUs** (EC2 Fleet `TargetCapacityUnitType=vcpu`):
each pair needs `ec2_worker_vcpus`, AWS packs instances until the vCPU target is met, and each
instance auto-packs `floor(min(vCPU/ec2_worker_vcpus, mem/ec2_worker_memory_mb))` pairs at boot.
Instance **types** come from the selected `orb_template_id` (an ABIS range or an enumerated list) -
there is no single `ec2_instance_type`. Worker container CPU/memory *limits* still come from
`agent_configuration.{agent,lambda}.{maxCPU,maxMemory}` in the config (one place, shared with EKS).

---

## 7. Teardown

```bash
make auto-destroy-custom-runtime TAG=$TAG REGION=$AWS_REGION   # grid + ORB + workers
make auto-destroy-images TAG=$TAG REGION=$AWS_REGION           # ECR (only if no other deploy needs them - repos are region-global)
make delete-grid-state TAG=$TAG REGION=$AWS_REGION             # LAST: state buckets + CFN stack
```

Or use the failure-tolerant teardown script:
`./scripts/destroy-htc-eks.sh --tag $TAG --region $AWS_REGION [--delete-state] [--force-orphans]`

> ORB creates a launch template per fleet request and may leak them (no sweeper in v1); check for
> orphaned launch templates after teardown.

---

## 8. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Tasks never complete; worker up but RIE container missing | `lambda:provided` not in this region → run step 3C (`init-images` + `transfer-images`) |
| `config-ec2` produced an EKS config | You ran `happy-path`/`upload-c++` after it → re-run `config-ec2` last |
| Apply fails on `RepositoryAlreadyExistsException` | ECR repos are region-global; don't run `transfer-images` if they exist - build only worker images |
| No workers ever launch | Backlog below threshold, or `orb_max_vcpus=0`; check capacity controller logs |
| ORB request fails: `Template validation failed - instanceType: machine_types must be specified` | `orb_template_id` is set to `EC2Fleet-Instant-ABIS`. orb-py's `_validate_prerequisites` (`base_handler.py`) requires `machine_types`/`launch_template_id` and never consults `abis_instance_requirements`, so an ABIS-only template is rejected before the (ABIS-capable) Fleet builder runs - an upstream orb-py bug. Use the enumerated `EC2Fleet-Instant-OnDemand` (the default) until it is fixed |
| Controller logs `no vcpu or memory data ... defaulting to 1 worker per instance` (ERROR) | ORB status returned no `vcpus` for a machine, so vCPU-accurate sizing degraded to 1 worker/instance; confirm the deployed orb-py 1.7.0 populates `provider_data.vcpus` (1.6.2 left it empty for RunInstances machines) |
| Worker can't reach Redis/SQS | Worker SG is egress-only; confirm it's in the control-plane VPC/subnets |
