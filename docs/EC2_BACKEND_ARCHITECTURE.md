# HTC-Grid EC2 Worker Backend - Architecture & Operations

This document describes the **EC2 worker-plane backend** for HTC-Grid: an alternative to the
default EKS backend in which the Agent+Lambda-RIE worker runs on plain EC2 instances under Docker
Compose, and the fleet is dynamically scaled by **ORB** (FINOS Open Resource Broker) driven by a
queue-watching capacity controller. The control plane and VPC are shared with the EKS backend,
unchanged.

It was implemented as selectable Terraform (`worker_backend = "eks" | "ec2"`) and **validated
end-to-end on a live fresh grid** (`project_name = ec2t1`, `eu-west-1`): ORB launched a real
worker, the worker auto-computed and ran 2 pairs, 52 mock tasks finished (26 per pair, client
"All results verified"), and the controller reconciled capacity by invoking the orchestrator.

---

## 1. Backend selection

A single Terraform root deploys either backend, chosen by one variable:

```hcl
worker_backend = "eks"   # default - Helm/KEDA worker pods (unchanged)
worker_backend = "ec2"   # EC2 + Docker Compose pairs, scaled by ORB
```

`deployment/grid/terraform/main.tf` gates the modules with `count`:

| Module | eks | ec2 |
|---|---|---|
| `vpc`, `control_plane` | ✅ always | ✅ always (reused unchanged) |
| `compute_plane` (EKS), `htc_agent` (Helm/IRSA), `kubernetes_config_map` | ✅ | ⛔ count=0 |
| `compute_plane_ec2`, `orb_orchestrator`, `capacity_controller`, `aws_ssm_parameter.agent_config` | ⛔ count=0 | ✅ |

The `kubernetes`/`helm` providers are configured from `compute_plane` outputs via
`try(module.compute_plane[0].x, fallback)` so they resolve harmlessly when EKS is absent (no k8s
resource is ever instantiated on the ec2 path). `moved {}` blocks keep an existing EKS state from
churning when upgrading to the selectable layout.

---

## 2. Architecture

```
                       SQS task queue(s) ApproximateNumberOfMessages (backlog)
                                  │  (read directly; scaling_metrics/pending_tasks_ddb is EKS-only)
   EventBridge rate(1 min) ─► capacity_controller Lambda (NEW, outside VPC)
                                  │  reads backlog (SQS) + ORB live machines' vCPUs; reconciles in vCPUs
                                  │  single-flight via reserved concurrency = 1
                                  │  Lambda→Lambda Invoke
                                  ▼
                       orb_orchestrator Lambda (zip: orb-py 1.7.0, python3.11, outside VPC)
                                  │  create(vCPU target) / status / terminate   state → 3× DynamoDB (orb-<proj>-*) + CMK
                                  ▼  EC2 Fleet Instant, TargetCapacityUnitType=vcpu (template baked at deploy time; iam:PassRole worker role)
                       EC2 worker (AL2023, private subnet, instance profile, IMDSv2 hop=3)
                                  │  cloud-init (SSM-delivered): install Docker + compose(from S3) →
                                  │  pull agent config from SSM → ECR login →
                                  │  NUM_PAIRS = min(vCPU/pair_cpu, memMB/pair_memory) → render compose → up -d
                                  ▼
                       N × [ getlayer-i → rie-i (:8080) → agent-i ]   (each pair: own net+pid ns, own /var/task)
                                  │  long-poll claim / heartbeat / invoke RIE / results
                                  ▼
                       SQS · DynamoDB · ElastiCache Redis · S3   (control plane, reused)
                       container stdout → awslogs → /aws/ec2/<cluster>/worker-logs
```

### Components (all new, under `worker_backend=ec2`)

**`compute_plane_ec2/`** - defines the worker (not a running fleet):
- IAM instance role + profile: attaches the control-plane `htc_agent_permissions_policy_arn`
  (same perms the EKS agent gets via IRSA) + `AmazonSSMManagedInstanceCore` +
  `AmazonEC2ContainerRegistryReadOnly` + an inline policy for SSM config read & worker-log writes.
- Egress-only security group (Redis reachable via the control-plane Redis SG's VPC-CIDR rule).
- A dedicated CMK + CloudWatch log group `/aws/ec2/<cluster>/worker-logs`.
- An AL2023 AMI lookup and the rendered cloud-init `user-data.sh.tftpl` (exported as
  `worker_ami_id` / `worker_user_data_plain` for ORB). ORB builds its own EC2 Fleet launch template
  per request from the baked ORB template - there is no standalone `aws_launch_template` resource.
- **`user-data.sh.tftpl`** computes `NUM_PAIRS` at boot, then a bash loop renders an N-pair
  `docker-compose.yml`: each pair = `getlayer-i` (S3 lambda.zip → /var/task) → `rie-i`
  (`lambda:provided`, :8080) → `agent-i` with `network_mode`/`pid: service:rie-i`, unique
  `MY_POD_NAME=<instance-id>-pair-i`, and the `awslogs` driver.
- **Per-container resource limits** (`cpus` + `mem_limit` on `rie-i`/`agent-i`) come from the
  **same `agent_configuration` block the EKS backend uses** - there is ONE place to set them.
  The root reads `agent_configuration.{agent,lambda}.{maxCPU,maxMemory}` (defaults in
  `local.default_agent_configuration`) and passes them to **both** `htc_agent` (EKS, as chart
  requests/limits) and `compute_plane_ec2` (EC2, converted millicores→cores and MiB→`m`). So
  tuning the worker pair's CPU/memory is a single edit in `grid_config.json`'s
  `agent_configuration`, regardless of backend.

**`orb_orchestrator/`** - the fleet orchestrator (ORB), ported from the proven CDK PoC:
- 3 DynamoDB state tables (`orb-<proj>-{machines,requests,templates}`, PK `id`:S, PITR, CMK).
- **ZIP-packaged** Lambda (NOT a container image): built in the SAM build container like every
  other htc-grid Lambda - the lambda module stages `orb_lambda.py` + the rendered `config/` and
  `pip install`s `orb-py==1.7.0` (unmodified; its DynamoDB backend works out of the box, so there
  is no patch step). Runs on `python3.11`, outside any VPC, 512 MB / 300 s. No Dockerfile,
  no ECR repo, no image-build step.
- Least-privilege role: DDB RW on the 3 tables, EC2 launch-template + **CreateFleet/DescribeFleets/
  DeleteFleets/ModifyFleet** + run/terminate/describe + `DescribeInstanceTypes`, SSM AMI read, KMS,
  and **`iam:PassRole`** on the worker role. (No SSM user-data read anymore - user_data is baked in.)
- Grid-specific config reaches ORB two ways, so one build works for any grid:
  region + DynamoDB table prefix are read by **orb-py's own `ORB_AWS_*` env layer**
  (`AWSProviderConfig` is a pydantic-settings `BaseSettings`: `ORB_AWS_REGION`,
  `ORB_AWS_STORAGE__DYNAMODB__{TABLE_PREFIX,REGION}`), while the template values - subnet, SG,
  instance profile, AMI, user_data, and instance selection - are **merged into the selected
  `aws_templates.json` template at DEPLOY TIME by Terraform** and baked into the zip (a `local_file`
  staged into the package; `hash_extra` forces a repackage on change). The handler no longer
  materializes anything at cold start (it only asserts the table prefix is set);
  `ORB_ALLOW_TERMINATE_ALL` is unset (kill switch disabled). See ADR-006.

**`capacity_controller/`** - the scaling brain (scales in **vCPUs**, ADR-006):
- EventBridge `rate(1 minute)` → Lambda (outside VPC - it only calls regional AWS APIs: Lambda, SQS, DynamoDB, EC2/SSM).
- Reads backlog directly from SQS (`get_queue_length` → `ApproximateNumberOfMessages`) + each ORB
  **live** machine's `vcpus` (from `status`), computes
  `desired_vcpus = clamp(ceil(backlog / TARGET_PENDING_PER_PAIR) * PAIR_CPU, MIN_VCPUS, MAX_VCPUS)`
  and `current_vcpus = Σ vcpus(active)`, then invokes the orchestrator `create` with the **vCPU
  deficit** (scale-up) or cordons surplus instances for graceful drain (scale-down, ADR-005). If a
  machine reports no `vcpus`/`memory_mib`, `_vcpus_of` logs an ERROR and falls back to 1 worker per
  instance.
- Single-flight via the Lambda's `reserved_concurrent_executions = 1` (ADR-001) prevents
  overlapping ticks from double-issuing (ORB `request_machines` is not idempotent). See
  `docs/architecture_design_decisions.md`.

### Config delivery
The ~45-key agent config (`Agent_config.tfvars.json`) is published to **SSM Parameter Store
SecureString** (`/htc/<proj>/agent_config`, Advanced tier, CMK-encrypted), pulled at boot and
bind-mounted to `/etc/agent`. On the ec2 backend `metrics_are_enabled` is forced to `0` for **both**
the agent config and the control-plane Lambdas (there is no in-cluster InfluxDB).

---

## 3. Differences vs the EKS backend

| Concern | EKS | EC2 |
|---|---|---|
| Worker host | Pod on managed node group | EC2 instance, Docker Compose |
| Pair isolation | pod `shareProcessNamespace` | per-pair `network_mode`+`pid: service:rie-i` |
| Scaling | KEDA + Cluster Autoscaler | capacity_controller Lambda (scales in **vCPUs**) + ORB orchestrator |
| Demand signal | `scaling_metrics` → CloudWatch `pending_tasks_ddb` (KEDA reads it) | controller reads SQS `ApproximateNumberOfMessages` directly (`scaling_metrics` not deployed) |
| Capacity unit | pod replicas | total fleet **vCPUs** (EC2 Fleet `TargetCapacityUnitType=vcpu`); each instance auto-packs `floor(vCPU/pair_cpu)` pairs |
| Identity | IRSA (`htc-agent-sa`) | EC2 instance profile (same permission policy) |
| Config | ConfigMap `agent-configmap` | SSM SecureString → `/etc/agent` |
| Container logs | FluentBit → `/aws/eks/<cluster>/aws-fluentbit-logs` | awslogs → `/aws/ec2/<cluster>/worker-logs` |
| Drain on scale-in | node_drainer Lambda | controller-owned cordon→sweep→ORB-terminate (ADR-005) |
| Capacity API | n/a | ORB **EC2 Fleet Instant**, prebuilt template selected by `orb_template_id` (ABIS / enumerated / spot) |

Shared & unchanged: VPC + endpoints, SQS, DynamoDB, Redis, S3, Cognito, API Gateway, the
control-plane Lambdas (except `scaling_metrics`, now EKS-only), and the `grid_errors-<proj>`
application error log.

---

## 4. Deploy (operator runbook)

```bash
TAG=<project>; REGION=eu-west-1
# 1. state buckets
make init-grid-state TAG=$TAG REGION=$REGION
# 2. build/push the WORKER images for this project tag (ECR repos are account-wide):
#    awshpc-lambda, lambda-init, submitter (+ shared lambda:provided), and lambda.zip.
#    NOTE: the ORB orchestrator is NOT an image - it is zip-built by Terraform at apply time
#    (pip-installs orb-py inside the SAM build container), so no image build is needed.
make lambda lambda-init TAG=$TAG REGION=$REGION
make -C examples/submissions/k8s_jobs build push TAG=$TAG REGION=$REGION
make -C examples/workloads/c++/mock_computation upload TAG=$TAG REGION=$REGION ACCOUNT_ID=<acct>
# 3. generate the ec2 config + deploy (terraform zip-builds the orchestrator + controller Lambdas)
make config-ec2 TAG=$TAG REGION=$REGION
cd deployment/grid/terraform
terraform init -reconfigure -backend-config="bucket=$TAG-htc-grid-tfstate-..." ...
terraform apply -var-file=<repo>/generated/grid_config.json
```

Knobs (in `ec2_worker_grid_config.json.tpl` / root variables): `orb_template_id`
(default `EC2Fleet-Instant-OnDemand`; ABIS is currently blocked by an orb-py validator bug, see §6),
`ec2_worker_vcpus`, `ec2_worker_memory_mb`,
`orb_target_pending_per_pair`, `orb_min_vcpus`, `orb_max_vcpus`, `orb_max_instances`,
`orb_control_interval`. Instance **types** come from the selected template (ABIS range or
enumerated list), not a single `ec2_instance_type`. See the deployment guide for the full table.

> **Note:** ECR pull-through cache rules (`quay`, `registry-k8s-io`, `ecr-public`) are
> account-global and EKS-only; a second grid in the same account should **skip** `transfer-images`
> and build only the EC2-needed images (as above).

---

## 5. Validation performed (live, project `ec2t1`)

> The live validation below ran with the ORB orchestrator packaged as a **container image** on
> orb-py 1.6.2 (which required 4 cold-start DynamoDB patches). It has since been converted to a
> **zip Lambda** (SAM build container, python3.11) on unmodified **orb-py 1.7.0** (DynamoDB fixes
> upstreamed, no patches); the live create→status→terminate loop on this build should be re-run
> end-to-end.

| # | Test | Result |
|---|---|---|
| 1 | `terraform plan` (ec2) | 241 resources; **0** EKS/k8s/helm/node_drainer; worker+orchestrator+controller present ✓ |
| 2 | `terraform apply` | full grid + control plane, no EKS cluster ✓ |
| 3 | ORB orchestrator create→status→terminate | launched real `m6i.large`, status returned instance id, terminate worked ✓ |
| 4 | Worker bootstrap | `NUM_PAIRS=2` auto-computed; 4 containers (2 agents + 2 RIEs) up; getlayer exited 0 ✓ |
| 5 | End-to-end tasks | 52 finished, **pair-0=26 / pair-1=26**; submitter "All results are verified!" ✓ |
| 6 | Capacity controller | `backlog=0 live=2 → scale_down`, invoked orchestrator terminate ✓ |

### Bugs found and fixed during the live test
1. **ORB config table-prefix / IDs** were hardcoded to the PoC (`orb-poc`, PoC subnet/SG). Fixed by
   driving the table prefix + region through orb-py's own `ORB_AWS_*` env layer (so the bundled
   `config.json` ships grid-agnostic) and having the handler substitute the template-only values
   (subnet, SG, instance profile, AMI, instance type) into `aws_templates.json` at cold start.
2. **Worker got no user-data** - ORB's `RunInstances` template had no `user_data`. Fixed by storing
   the rendered cloud-init in SSM and injecting it into the template `user_data` field at cold start.
3. **Control-plane Lambdas crashed (502)** initializing the InfluxDB perf tracker. Fixed by passing
   `metrics_are_enabled = 0` to `control_plane` on the ec2 backend (not just the agent config).
4. **node_drainer empty-`Resource` IAM error** - gated the node_drainer (EKS-only) off via an
   explicit `enable_node_drainer` flag.
5. **capacity_controller hung (120 s timeout)** - it was VPC-attached but the VPC has no `lambda`
   endpoint/NAT. Fixed by running the controller outside the VPC (it only calls regional AWS APIs -
   Lambda, SQS, DynamoDB, EC2/SSM).
   (At the time this also wedged a DynamoDB single-flight lock until its TTL; that lock was later
   removed in favour of `reserved_concurrent_executions = 1` - ADR-001.)
6. **compose-plugin staging** `null_resource` didn't `mkdir` its cache dir. Fixed.

---

## 6. Known limitations / deferred (v1)

- **Graceful drain IS implemented** (ADR-005): controller-owned cordon→sweep→ORB-terminate, gated on
  the live-task heartbeat. The `drain_deadline` backstop still force-terminates stragglers (re-queued
  by `ttl_checker`), so idempotent tasks are still assumed. The systemd `htc-workers` unit + async
  Step Functions drain remain deferred.
- **EC2 Fleet Instant is the capacity API**, with capacity counted in vCPUs (ADR-006). The default
  is the **enumerated** `EC2Fleet-Instant-OnDemand` template (a `machine_types` list). The
  `EC2Fleet-Instant-ABIS` template is **currently unusable**: orb-py's `_validate_prerequisites`
  (`base_handler.py`) requires `machine_types`/`launch_template_id` and never consults
  `abis_instance_requirements`, so an ABIS-only template is rejected at create
  (`machine_types must be specified`) before the ABIS-capable Fleet builder runs - an upstream
  orb-py bug. `EC2Fleet-Instant-Spot` exists but is unproven end-to-end; re-prove
  `create→status→terminate→drain` before relying on Spot.
- **`vcpus` may be missing from ORB status.** The vCPU-unit math relies on each machine reporting
  `vcpus`; some orb-py builds persist an empty `provider_data` (seen live on 1.6.2 for RunInstances
  machines), which trips the controller's "1 worker per instance" fallback. orb-py 1.7.0 still
  derives `vcpus` via the same `derive_cpu_ram_from_instance_type` path, so confirm the deployed
  1.7.0 build populates `provider_data.vcpus`, or have the controller resolve it via `DescribeInstanceTypes`.
- **ORB launch-template leak** - ORB creates a launch template per fleet request and doesn't delete
  it; add a sweeper.
- **No Grafana/InfluxDB/Prometheus**; agent perf metrics off. Container logs go to CloudWatch.
- **orb-py is pinned to 1.7.0** (unmodified - the DynamoDB fixes that 1.6.2 needed as 4 cold-start
  patches are now upstream). Re-prove the create/status/terminate loop on any version bump.
- **Single-flight via `reserved_concurrent_executions = 1`** (ADR-001): an overlapping scheduled
  tick is throttled and async-retried (deferred re-run) rather than cleanly skipped. Harmless at
  1/min with sub-300 s ticks; revisit if multiple invokers or near-timeout ticks appear.

---

## 7. File structure - all changed (~) and new (+) files

Legend: `+` new file/dir, `~` modified existing file.

```
htc-grid/
├── Makefile                                              ~ add `config-ec2` target (+ .PHONY)
│
├── deployment/
│   ├── grid/terraform/
│   │   ├── main.tf                                       ~ worker_backend selection; count-gate eks modules;
│   │   │                                                   try([0]) refs; moved{} blocks; wire ec2 modules + SSM/S3
│   │   ├── providers.tf                                  ~ try(module.compute_plane[0]...) so k8s/helm providers
│   │   │                                                   resolve harmlessly when EKS is absent
│   │   ├── variables.tf                                  ~ add worker_backend (validated) + ec2_*/orb_* knobs
│   │   ├── outputs.tf                                    ~ grafana output → try([0]); guard EKS-only outputs
│   │   ├── agent-config.tf                               ~ metrics_are_enabled_effective; ConfigMap count-gated to eks
│   │   ├── .gitignore                                    ~ ignore .cache/ (compose-plugin staging) + agent_config.json
│   │   │
│   │   ├── control_plane/                                (shared, mostly untouched - one EKS-only gate)
│   │   │   ├── main.tf                                   ~ add node_drainer_enabled local (gated on enable_node_drainer)
│   │   │   ├── variables.tf                              ~ add enable_node_drainer; default eks_managed_node_groups={}
│   │   │   ├── lambda_node_drainer.tf                    ~ count-gate node_drainer (fixes empty-Resource IAM error on ec2)
│   │   │   └── outputs.tf                                ~ node_drainer_lambda_role_arn → try([0])
│   │   │
│   │   ├── compute_plane_ec2/                            + NEW MODULE: the EC2 worker definition (renamed from worker_plane_ec2)
│   │   │   ├── main.tf                                   + locals, AL2023 AMI lookup, user-data render
│   │   │   ├── variables.tf                              + region/vpc/ecr/ssm/pair-sizing/etc. inputs
│   │   │   ├── outputs.tf                                + role/profile/SG/AMI/log-group/user-data outputs (for ORB)
│   │   │   ├── iam.tf                                    + instance role+profile (agent policy + SSM/ECR/logs)
│   │   │   ├── sg.tf                                     + egress-only worker security group
│   │   │   ├── logs.tf                                   + CMK + /aws/ec2/<cluster>/worker-logs log group
│   │   │   └── user-data.sh.tftpl                        + cloud-init: NUM_PAIRS auto-compute → render N-pair compose
│   │   │      (no launch_template.tf: ORB builds its own EC2 Fleet LT per request)
│   │   │
│   │   ├── orb_orchestrator/                             + NEW MODULE: ORB fleet orchestrator (zip Lambda; ported from CDK PoC)
│   │   │   ├── main.tf                                   + 3 DDB tables + CMK + ZIP Lambda + IAM; renders the selected
│   │   │   │                                               template (grid-completed) into .orb-config-staging at deploy time
│   │   │   ├── variables.tf                              + table prefix, lambda_runtime, worker role/profile/subnet/SG/AMI, orb_template_id, pair sizing
│   │   │   └── outputs.tf                                + function name/arn, table name, key arn
│   │   │
│   │   └── capacity_controller/                          + NEW MODULE: queue-driven scaling controller (vCPU unit)
│   │       ├── main.tf                                   + EventBridge tick + Lambda (reserved concurrency=1) + IAM
│   │       └── variables.tf                              + orchestrator fn, task queue + SQS CMK, pair_cpu/pair_memory, min/max_vcpus, target_per_pair, interval
│   │
│   └── (image_repository/terraform/*, init_grid/cloudformation/grid_state.yaml ~ pre-existing local mods, not part of this work)
│
├── source/compute_plane/
│   ├── orb_orchestrator/                                 + NEW: ORB orchestrator ZIP-build source (no Docker/ECR)
│   │   ├── orb_lambda.py                                 + create/status/terminate dispatch (no cold-start substitution; asserts table prefix)
│   │   ├── requirements.txt                              + orb-py==1.7.0 (unmodified; DynamoDB fixes upstream, no patches)
│   │   ├── .gitignore                                    + ignore build artifacts (__pycache__, *.pyc)
│   │   ├── test_orb_lambda.py                            + unit tests (status reconcile, table-prefix assert, shipped config invariants)
│   │   ├── config/config.json                            + ORB storage(dynamodb)+provider config (grid-agnostic; region/table_prefix via ORB_AWS_* env)
│   │   └── config/aws_templates.json                     + prebuilt template catalog: EC2Fleet-Instant {ABIS, OnDemand, Spot} (vcpu unit)
│   │
│   └── python/lambda/capacity_controller/
│       └── ec2_capacity_controller.py                    + controller logic: read backlog (SQS get_queue_length)+live, reconcile, invoke orchestrator
│
├── examples/configurations/
│   ├── ec2_worker_grid_config.json.tpl                   + NEW: ec2-backend grid config template (worker_backend=ec2)
│   └── Makefile                                          ~ add generated-ec2 target + ec2_*/orb_* knob defaults
│
└── docs/
    ├── EC2_BACKEND_ARCHITECTURE.md                       + NEW: this document
    └── diagrams/ec2-worker-architecture.md               + NEW: Mermaid + ASCII architecture diagrams
```

> Historical references (not part of the Terraform deliverable): `ec2-worker-asbuilt-report.md` and
> `ec2-worker-test-plan.md` (manual-PoC docs, marked superseded); `architecturev2.md` and
> `DEPLOY_ORB_IN_LAMBDA_WITH_HTC_GRID.md` (input design docs). The manual `deployment/ec2_worker/`
> PoC artifacts were deleted (superseded by `compute_plane_ec2/`).

---

## 8. Q&A (design rationale)

> For an operational / scale-down FAQ (busy detection, drain deadlines, the ORB seam, failure
> modes), see [`EC2_BACKEND_FAQ.md`](./EC2_BACKEND_FAQ.md). The questions below cover module-layout
> rationale.

**Why is `orb_orchestrator` a sibling of `control_plane`, not inside it?**
`control_plane` is the shared, always-on layer (deploys on both backends); ORB is an EC2-only
worker-plane scaler that *depends on* `compute_plane_ec2` outputs. Nesting it in `control_plane`
would couple a shared module to an optional feature and invert the dependency into a cycle.

**Why not put ORB under `compute_plane`?**
`compute_plane` *is* the EKS implementation (`count=0` on EC2). ORB would be dead there exactly
when it's needed. ORB is the EC2 analogue of KEDA+Cluster-Autoscaler, so it sits beside
`compute_plane_ec2`.

**Is `scaling_metrics` used on the ec2 backend?**
No - it is **EKS-only** now (gated by `enable_scaling_metrics = worker_backend == "eks"`, the
same pattern as `node_drainer`). It is an EventBridge `rate(1 minute)` Lambda that reads the SQS
backlog and `put_metric_data` publishes it as `pending_tasks_ddb` for KEDA to consume. The ec2
`capacity_controller` reads the same `ApproximateNumberOfMessages` straight from SQS instead, so
the CloudWatch republish hop (and that Lambda) is not deployed on ec2.

**Why gate only `node_drainer`, not all of EKS?**
All of EKS *is* gated - `compute_plane`/`htc_agent` are `count=0` on EC2. `node_drainer` is the one
EKS-only resource that lives inside the shared `control_plane` module, so it needs its own
`enable_node_drainer` gate (its empty-`Resource` IAM policy would otherwise fail on EC2).

**Does the EC2 backend use an ASG?**
No. ORB launches instances via `RunInstances`. The only "ASG" in the code comment refers to the
EKS managed-node-group's own Auto Scaling Group (what `node_drainer` hooks into).

**Why is ORB a zip Lambda now instead of a container image?**
Consistency with every other htc-grid Lambda (no Dockerfile/ECR/image-build step). It's built in
the SAM build container, which pip-installs `orb-py` (unmodified) before zipping.

**How do I size the worker pair's CPU/memory?**
One place - `agent_configuration.{agent,lambda}.{maxCPU,maxMemory}` in `grid_config.json` - feeds
**both** backends (EKS chart limits and EC2 `cpus`/`mem_limit`). Separately, `ec2_worker_vcpus`/
`ec2_worker_memory_mb` are the *packing budget* that decides `NUM_PAIRS` per instance at boot, and
`ec2_worker_vcpus` is also the controller's pairs↔vCPUs conversion factor (ADR-006), so the boot-time
pair count and the controller's vCPU accounting stay consistent.
