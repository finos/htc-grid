# HTC-Grid EC2 Backend - Architecture Design Decisions (ADR)

Running log of notable design decisions for the EC2 worker-plane backend. Newest first.

---

## ADR-006: Scale in vCPUs via EC2 Fleet; prebuilt template catalog selected by id

**Status:** Decided - the capacity controller and ORB operate in a single **vCPU** unit, ORB launches
an **EC2 Fleet (Instant)** with `TargetCapacityUnitType=vcpu`, and the worker template is chosen from a
**prebuilt catalog** by `orb_template_id` and grid-completed + baked into the orchestrator zip at
**deploy time**. Supersedes the v1 "RunInstances on-demand, scale by instance count, substitute the
template at cold start" approach.

**Context.**
v1 scaled by *instance count* (`desired = ceil(backlog / target_pending_per_instance)`) and launched a
single instance type via `RunInstances`. Two problems: (1) "number of instances" is not a stable
capacity unit once a fleet is heterogeneous - a `*.large` and a `*.xlarge` are not equal capacity, so
the math under-counts (the old `line 219` TODO); (2) instance selection was a single hardcoded type,
and the grid-specific template values (subnet/SG/profile/AMI/user_data) were substituted into
`aws_templates.json` by the handler at **cold start** (`_materialize_grid_config`), which also fetched
user_data from SSM. We also wanted Attribute-Based Instance Selection (ABIS) without the controller
having to understand it.

**Decision.**
- **vCPU is the capacity unit.** A pair needs `pair_cpu` vCPUs; an instance auto-packs
  `floor(min(vCPU/pair_cpu, mem/pair_memory))` pairs at boot. The controller computes
  `desired_pairs = ceil(backlog / target_pending_per_pair)`,
  `desired_vcpus = clamp(desired_pairs * pair_cpu, min_vcpus, max_vcpus)`,
  `current_vcpus = Σ vcpus(active)`, and asks ORB to `create` the vCPU **deficit**.
- **EC2 Fleet Instant with `TargetCapacityUnitType=vcpu`.** ORB's `create` count is a vCPU target;
  AWS packs a mix of instances (ABIS- or list-selected) until their vCPUs meet it, and uses each
  instance's real vCPU as its weight. This is set via the template's `provider_api_spec` (deep-merged
  over ORB's default fleet spec). Instant returns instance IDs synchronously and terminates explicit
  IDs with no delete-at-zero hazard (unlike ASG, ADR-004), so the ADR-005 drain works unchanged.
- **The controller reads `vcpus` from ORB `status`** (`provider_data.vcpus`, also surfaced top-level
  by the default scheduler) - no `DescribeInstanceTypes` call, no extra IAM. `_vcpus_of` falls back:
  real `vcpus` → size by `memory_mib` → if neither, log an **ERROR** and default to 1 worker per
  instance (so the controller never crashes or counts zero, but the degradation is loud).
- **Prebuilt template catalog, selected by id.** `config/aws_templates.json` ships a small curated
  catalog (`EC2Fleet-Instant-{ABIS,OnDemand,Spot}`), every entry an EC2 Fleet with the vcpu unit. The
  user picks one via `orb_template_id`; instance selection (ABIS range vs enumerated list) lives in
  the template, **not** in grid_config. The controller is blind to which - it only sends a vCPU count.
- **Deploy-time bake, not cold-start substitution.** Terraform merges the grid infra fields
  (subnet/SG/profile/AMI/user_data) into the selected template and writes it to a staging dir baked
  into the zip (`local_file` + `hash_extra` forces a repackage on change). `_materialize_grid_config`
  is removed; the handler only asserts the table prefix. The orchestrator gains `ec2:CreateFleet`/
  `Describe/Delete/ModifyFleet` + `DescribeInstanceTypes`; it loses the SSM user-data read.
- **Config knobs renamed/removed:** `ec2_pair_cpu`→`ec2_worker_vcpus`,
  `ec2_pair_memory`→`ec2_worker_memory_mb`; `orb_min_instances`/`orb_target_pending_per_instance`
  →`orb_min_vcpus`/`orb_max_vcpus`/`orb_target_pending_per_pair`; `ec2_instance_type` and
  `ec2_pairs_per_instance` deleted (types come from the template; pairs are always auto-packed). The
  standalone `aws_launch_template` was removed (ORB builds its own per fleet request).

**Consequences / trade-offs.**
- Heterogeneous fleets now scale correctly: requested vCPUs ≈ delivered capacity. The `line 219` TODO
  is closed.
- **`vcpus` must actually be present in ORB status.** Verified live on a real grid: deployed orb-py
  1.6.2 returned an EMPTY `provider_data` for RunInstances machines, so the controller fell back to
  1-worker-per-instance every tick. orb-py 1.7.0 (now pinned) still derives `vcpus` via the same
  path; confirm the fleet path populates it on 1.7.0, else the vCPU benefit is lost (the fallback
  keeps things running, loudly). See `orb-status-exposes-vcpus`.
- A single Fleet uses one shared launch template, so a fixed `pairs_per_instance` override can't be
  applied per type - pairs are always auto-packed from real capacity (this is why the override knob
  was removed).

**Revisit if:** ORB stops reporting `vcpus` reliably (then resolve it controller-side via
`DescribeInstanceTypes`), or a non-Fleet capacity API is needed (the catalog + vcpu-unit assumptions
are Fleet-specific).

**Related:** [[ADR-005]] (controller-owned drain, preserved), [[ADR-004]] (why ASG is unusable; Instant
fleets avoid its delete-at-zero trap), [[ADR-002]] (brain/hands split, preserved), [[ADR-001]]
(single-flight).

---

## ADR-005: Controller-owned drain core; ORB terminates (ORB owns the API choice)

**Status:** Decided - the controller owns a **provider-independent drain core** (cordon,
idle-detect, sweep) and asks ORB to terminate the idle instances it selects. ORB stays the single
capacity abstraction: it picks the AWS API (RunInstances / EC2Fleet / ASG, possibly different per
request) and decrements the right request on terminate. A polymorphic provider seam was considered
and **dropped** - ORB already abstracts the capacity API, so a second seam earns nothing today.

**Context.**
ADR-003's graceful drain was entangled with ORB: the controller invoked ORB actions
`cordon`/`uncordon`/`terminate`, and ORB owned the SSM `docker compose stop` + the EC2 drain tags.
But draining is **provider-independent** - cordon (SSM stop), idle-detection (the heartbeat query),
and drain-state (EC2 tags) are EC2-level functions identical no matter how an instance was
provisioned. ADR-004 showed ORB's ASGCapacityManager can never host an ASG lifecycle hook, so the
*controller* (not the capacity API) must own drain for it to work across RunInstances / EC2Fleet /
ASG.

**Decision.**
- **DRAIN is EC2-level and controller-owned** (`drain.py`) - cordon = SSM `compose stop` +
  `htc:lifecycle`/`htc:drain_deadline` tags; idle-detect = the task heartbeat; sweep =
  terminate-when-idle/expired or uncordon. Universal across every provisioning API.
- **The KILL goes through ORB** (`orb_client.terminate(ids)`), never a bare `ec2:TerminateInstances`
  from the controller. A self-healing API (ASG, Fleet-maintain) would relaunch a replacement if the
  instance were killed without decrementing desired, and ORB's bookkeeping would drift. ORB owns the
  API choice; the controller just hands it the idle ids. Preserves ADR-002 (controller = brain, ORB
  = hands).
- **ORB client, not a provider seam:** `orb_client.list_live()` / `create(n)` / `terminate(ids)`
  wraps the orchestrator's `status` / `create` / `terminate`. The polymorphic `CapacityProvider`
  seam (OrbProvider/AsgProvider) was dropped - ORB is already the capacity abstraction.
- **What moves:** the controller GAINS `ssm:SendCommand` + `ec2:CreateTags`/`DeleteTags`/
  `DescribeInstances` (boto3-only). The orchestrator LOSES `cordon`/`uncordon` and the `status`
  drain-tag enrichment; `DRAIN_DEADLINE_SEC` + the SSM/tag IAM move to the controller module.

**Crash recovery / idempotency.**
The controller is a **stateless reconciler**: it holds no durable state between ticks and
re-derives the world each tick from observed truth (`orb_client.list_live()`, the EC2 drain tags,
the heartbeat busy-set). `reserved_concurrent_executions = 1` (ADR-001) means ticks never overlap.
So a crash at a random point is generally self-healing - the next tick re-observes and re-converges:
- Crash mid-sweep after terminating some ids → killed ones drop out of `list_live`; the rest are
  re-evaluated next tick. Terminating an already-terminating instance is a no-op.
- Crash after reads, before any mutation → nothing happened; redone next tick.

Three real gaps and their mitigations:
- **Cordon is two non-atomic steps (CreateTags then SSM stop).** A crash between them leaves an
  instance tagged `draining` but never told to stop; the next tick routes it to the *sweep*, not
  back to cordon, so the stop would never be retried (it would work until its deadline, then get
  force-killed - avoidable task loss). **Mitigation (baked into the drain core): the sweep
  re-issues `compose stop` for any `draining` instance still in the busy set** (idempotent - a
  no-op if already stopping). Tag-before-stop ordering is kept (tagged-but-not-stopped is
  recoverable; stopped-but-not-tagged would look like idle live capacity).
- **ORB `create` is non-idempotent + async.** A crash after `create` launched instances but before
  they appear in `list_live` can make a fresh tick create again → transient over-provisioning until
  a later tick scales the surplus down. Mitigation: ensure ORB records the machine synchronously so
  `list_live` sees it on the next tick; client-token dedup is a follow-up.
- **ORB launch-template leak** (one per RunInstances request, not deleted) is amplified by
  crash-induced double-creates. Mitigation: a periodic launch-template sweeper (tracked ORB-quirks
  item).

No untracked-instance orphans originate in the controller itself (it tracks nothing; ORB's
`list_live` is the source of truth). The two real cost vectors are double-create over-provisioning
(self-correcting) and leaked launch templates (needs the sweeper).

**Revisit if:** the create double-launch window proves material (then add client-token dedup in
the ORB client / orchestrator), or a second capacity backend ever exists that ORB cannot abstract
(only then would a provider seam earn its place).

**Related:** [[ADR-004]] (why ASG hook drain is unavailable under ORB), [[ADR-003]] (the cordon/sweep
mechanism this refactors), [[ADR-002]] (brain/hands split, preserved), [[ADR-001]] (single-flight).

---

## ADR-004: ASG lifecycle-hook drain vs ORB - why we cannot use ASG draining today

**Status:** Decided - graceful scale-down stays **cordon + sweep under ORB** (ADR-003). ASG
lifecycle-hook draining is the cleaner primitive but is **incompatible with how ORB manages
capacity today**. Recorded so we stop re-deriving it; revisit only if ORB is removed from the
EC2 termination path.

**Context.**
A recurring question: can we let an EC2 Auto Scaling Group (ASG) drain workers gracefully on
scale-in, instead of the controller-driven cordon→sweep in ADR-003, and still have the
**controller decide which instances to terminate**? The answer is: the ASG mechanism is real and
attractive, but ORB's `ASGCapacityManager` bypasses it and would destroy a long-lived ASG. So it
is not available while ORB owns termination.

### (A) How ASG *could* handle draining (the target we cannot use yet)

A single, long-lived ASG with a **termination lifecycle hook** gives native, task-aware drain:

1. The ASG has a hook on `autoscaling:EC2_INSTANCE_TERMINATING`. Any termination of a **member**
   instance is **paused** in `Terminating:Wait` instead of killing immediately.
2. The controller (the brain) decides *which* instances to remove and calls
   **`TerminateInstanceInAutoScalingGroup(InstanceId, ShouldDecrementDesiredCapacity=true)`** for
   each chosen id. This overrides the ASG's own termination policy (we name the victims) **and**
   still routes through the lifecycle hook.
3. The hook fires → a drain handler (a Lambda, or an on-instance hook - mirrors the existing EKS
   `node_drainer`) runs `docker compose -p htc-workers stop`; the agent's SIGTERM handler finishes
   the in-flight task and stops claiming.
4. For long tasks the handler sends `RecordLifecycleActionHeartbeat` to extend the pause; when the
   worker is idle it calls `CompleteLifecycleAction(CONTINUE)` and only **then** does the ASG
   terminate the instance.
5. Backstop: if drain never completes, the hook timeout expires and the ASG terminates anyway;
   the unfinished task is re-queued by `ttl_checker`.

What this removes vs ADR-003: the `htc:lifecycle`/`htc:drain_deadline` tags, the `query_live_tasks`
busy-set query (and the controller's `dynamodb:Query`/`kms:Decrypt` grants + bundled DAL), and the
two-tick sweep. The ASG holds the instance; the controller just names victims; the hook drains.
The ASG must be **Terraform-owned and long-lived** (created once, deleted only by `terraform
destroy`; `min_size=0` so scale-to-zero is legal), and the actuator must be IAM-fenced to
**capacity-only** operations (`SetDesiredCapacity`, `TerminateInstanceInAutoScalingGroup`) - never
`Create/Update/DeleteAutoScalingGroup`.

### (B) Why this is currently NOT possible with ORB

ORB's `ASGCapacityManager.release_instances` does **not** terminate through the ASG. Its termination
path is:

1. `DetachInstances(ShouldDecrementDesiredCapacity=True)` (chunked 20) - **removes the instance
   from the ASG** and drops desired capacity.
2. `DescribeAutoScalingGroups` - read live `DesiredCapacity` after detach.
3. `UpdateAutoScalingGroup MinSize=new_capacity` - only if `MinSize > new_capacity`.
4. `ec2:TerminateInstances` - hard-kills the now-standalone instances.
5. If `new_capacity == 0` after detach (last instances removed): **`DeleteAutoScalingGroup
   (ForceDelete=True)`** + launch-template cleanup. The **same delete also runs in the fallback
   branch** when ASG details cannot be fetched.

Two independent, fatal incompatibilities with (A):

- **Detach + `ec2:TerminateInstances` bypasses the lifecycle hook.** The hook only fires when the
  **ASG** terminates a **member**. ORB detaches the instance first (so it is no longer a member),
  then kills it with a plain EC2 terminate. There is nothing for the hook to fire on - the drain
  is never triggered. ORB never calls `TerminateInstanceInAutoScalingGroup` (the one API that would
  honor the hook). So the entire (A) drain is dead on arrival under ORB.
- **ORB deletes the ASG at capacity 0 (and on read failure).** When the fleet scales to zero, ORB
  calls `DeleteAutoScalingGroup(ForceDelete=True)` - destroying a Terraform-owned, long-lived ASG
  out from under Terraform (state drift, lost hook + launch template, cannot scale back up).
  `ForceDelete=True` *also* bypasses lifecycle hooks. Worse, the same delete runs in the fallback
  branch when `DescribeAutoScalingGroups` fails, so a transient API error can destroy the ASG.

ORB treats an ASG as a **disposable, request-scoped wrapper** around `ec2:TerminateInstances`
(detach → kill → delete-when-empty). That is the opposite of the **persistent, hook-bearing ASG**
that (A) requires. The two models are mutually exclusive; you cannot get hook-drain while ORB owns
termination.

**Decision.**
Keep **cordon + sweep (ADR-003)** as the graceful-drain mechanism for the ORB-managed fleet. It is
in fact the *correct* pattern given ORB's detach/terminate semantics - there is no lifecycle hook to
lean on, so the controller must drain (cordon) before asking ORB to terminate. ASG hook-drain is
recorded as the preferred design **for if/when ORB leaves the EC2 termination path**.

**Revisit if:** we decide to drop ORB from the EC2 datapath. Then: a Terraform-owned long-lived ASG
+ a lifecycle-hook drainer (port the EKS `node_drainer`) + the controller calling
`TerminateInstanceInAutoScalingGroup` directly, IAM-fenced to capacity-only operations. At that
point ADR-003's cordon/tags/busy-query machinery is deleted. Note that, once the ASG provides both
scale-up (`SetDesiredCapacity`) and graceful scale-in (hook), ORB has little left to do on the EC2
backend - so this revisit is really the "remove ORB" decision.

**Related:** [[ADR-003]] (the cordon+sweep we keep), [[ADR-002]] (controller = brain, orchestrator =
actuator; that split is preserved in both models - only the actuator's downstream API changes),
[[ADR-001]] (single-flight controller).

---

## ADR-003: Graceful, task-aware scale-down via cordon + heartbeat-detected idleness

**Status:** Decided - scale-down is a two-phase **cordon → sweep → terminate** loop driven by
the capacity controller, using the *existing* task heartbeat as the busy signal. No new
DynamoDB index, no new table, no agent change, no Step Functions.

**Context.**
v1 scale-down picked the oldest live machines and terminated them immediately. Any task
in-flight on a terminated instance was killed and only recovered when `ttl_checker` re-queued
it after its heartbeat lapsed - lossy, and dependent on every task being idempotent. We want to
terminate only instances that have no in-flight work (or have exceeded a drain deadline),
without blocking the 1-minute control tick.

**What we reuse (nothing new on the hot path).**
- **Busy signal = the existing heartbeat.** Each agent, on claim and every
  `task_ttl_refresh_interval_sec`, writes `heartbeat_expiration_timestamp = now + offset` on
  its task row while it is `processing*`. A row that is `processing*` with
  `heartbeat_expiration_timestamp > now` is a pair working *right now*.
- **Index = the existing `gsi_ttl_index`.** It already projects `task_owner`. `ttl_checker`
  already queries it across all 32 state partitions with `heartbeat < now`; we add the mirror
  (`query_live_tasks`, `heartbeat > now`) and reuse the same throttle-skip guard.
- **Instance identity = the existing `task_owner`.** On EC2 `task_owner = "<instance-id>-pair-N"`
  (the instance id comes from IMDS in user-data), so `task_owner.split("-pair-")[0]` is the
  EC2 instance - the same id ORB uses as `machine_id`. No lookup, no join.
- **Drain = the agent's existing SIGTERM behaviour.** `docker compose -p htc-workers stop`
  (sent over SSM by the orchestrator) makes each agent's `GracefulKiller` finish its in-flight
  task and stop claiming new ones, within the compose `stop_grace_period` (1500s).

**Loop (each tick; single-flight by ADR-001).**
1. Read backlog + ORB `status` (now enriched with each machine's `htc:lifecycle` /
   `htc:drain_deadline` tags). `active` = live minus `draining`.
2. Compute the busy-instance set from `query_live_tasks`. If the state table is throttling,
   defer scale-down this tick (fail safe = keep capacity).
3. **Sweep `draining` instances:** not-busy → `terminate`; past `drain_deadline` → `terminate`
   anyway (stragglers re-queued by `ttl_checker`); backlog rebounded → `uncordon` (reclaim).
4. **Reconcile `active`:** surplus → **`cordon`** the victims (idle-first, then oldest); they
   become `draining` and a later tick's sweep terminates them once idle. Cordon ≠ terminate.

Because cordon stops new claims, once an instance leaves the busy set it stays out - no
terminate/claim race. An idle instance is cordoned on tick N and terminated on tick N+1.

**Decision rationale.** This is the minimal change that makes scale-down task-aware: it adds
no schema, no write amplification, and no new service, and it reuses a proven, throttle-aware
access pattern (`ttl_checker`'s 32-partition `gsi_ttl_index` fan-out). ORB stays the actuator
(ADR-002): the controller decides, the orchestrator performs the EC2 tag + SSM + terminate.

**Consequences / trade-offs.**
- Safety is **best-effort drain + `ttl_checker` backstop**: a task exceeding `drain_deadline` is
  still killed and re-queued (tasks are already assumed idempotent in v1).
- "Idle" means "idle within ~`heartbeat offset` (≈30s)"; fine for scale-down granularity.
- Two-tick latency to actually terminate (cordon, then sweep) - intentional, never blocks a tick.
- SSM cordon is best-effort; the `drain_deadline` tag guarantees eventual termination even if the
  SSM command never lands, so no instance can pin capacity forever.
- The controller now bundles the shared state-table DAL (`api-v0.1` + `utils`, boto3-only) and
  gains `dynamodb:Query` on the state table + its indexes; the orchestrator gains
  `ec2:DeleteTags` + `ssm:SendCommand`.

**Revisit if:** the 32-partition fan-out per tick becomes material at very large fleet sizes
(then a sparse instance-scoped registry/GSI keyed on idleness is the next step), or a hard
no-re-queue guarantee is required (then block termination while any task is in flight).

---

## ADR-002: Keep capacity_controller and orb_orchestrator as separate Lambdas

**Status:** Decided - **two separate Lambdas** (controller invokes orchestrator via
Lambda-to-Lambda). Revisit only if ORB init becomes cheap or the cross-invoke latency proves
material.

**Context.**
Both run on the ec2 backend. Could they be one Lambda? `capacity_controller` is the *brain*
(EventBridge `rate(1 min)` → read backlog + live count → decide), `orb_orchestrator` is the
*actuator* (ORB → EC2 create/status/terminate). Each controller tick invokes the orchestrator
at least once (`status`), plus `create`/`terminate` when scaling.

**Why separate.**
- **Cold-start weight.** The orchestrator pulls orb-py + its tree (pydantic, cryptography,
  sqlalchemy, boto3) and on every cold start builds a fresh ORB SDK client (seconds). The
  controller is boto3-only and fires every minute. Merging would put that heavy ORB init on the
  high-frequency metric path even on no-op/status-only ticks. (ORB doc B.2: keep the actuator a
  separate Lambda; do not fold ORB init into the high-frequency metric path; keep each invocation
  single-purpose.)
- **Roles / reuse.** Controller = decider, orchestrator = actuator (mirrors KEDA vs autoscaler
  on EKS). The orchestrator can be invoked by other callers (manual ops, future controllers),
  not just this one.
- **IAM blast radius.** The orchestrator owns the 3 DynamoDB state tables, EC2
  RunInstances/TerminateInstances, `iam:PassRole`, and a KMS key. The controller needs only
  `lambda:InvokeFunction`, `sqs:GetQueueAttributes`/`GetQueueUrl` (read the backlog),
  `dynamodb:Query` (busy set), and EC2 tag + `ssm:SendCommand` (drain). Merging would grant the
  scaling path the full EC2-launch IAM.
- **Concurrency model.** The controller is pinned to `reserved_concurrent_executions = 1`
  (ADR-001). The orchestrator must not be - it may be invoked concurrently (e.g. a status read
  while a create/terminate is in flight). One merged function cannot hold both policies.

**Consequences / trade-off.**
- Each tick pays a Lambda-to-Lambda invoke (and the orchestrator's cold-start latency on a cold
  invoke). Accepted. If it becomes material, the mitigation is **provisioned concurrency on
  `orb_orchestrator`** (keep ORB warm), not merging.

**Revisit if:** ORB initialization becomes cheap (e.g. a lighter client), or the per-tick invoke
latency/cost is shown to matter and provisioned concurrency is insufficient.

---

## ADR-001: Single-flight for the capacity controller - DynamoDB lock vs Lambda reserved concurrency

**Status:** Decided - use **`reserved_concurrent_executions = 1`**; remove the DynamoDB lock. Revisit if requirements change.

**Context.**
The `capacity_controller` Lambda runs on an EventBridge `rate(1 min)` schedule and reconciles
worker capacity by invoking the ORB orchestrator. Ticks can overlap (a slow tick - ORB cold-start
is several seconds - may still run when the next fires; EventBridge can also deliver more than
once). ORB's `create` (`request_machines`) is **not idempotent**, so two concurrent ticks could
each issue a create and double-launch capacity. We need at-most-one reconcile in flight.

**Options.**

| | DynamoDB lock (one-row conditional put + TTL) | `reserved_concurrent_executions = 1` |
|---|---|---|
| Overlapping tick | cleanly skips (no-op) | throttled, async-retried (runs slightly later) |
| Crashed tick | holds lock until ~300s TTL (stuck-state risk) | concurrency frees on exit - no stuck state |
| Cost / code | extra table + acquire/release + TTL handling | one attribute, zero code |
| Guards manual `aws lambda invoke` | yes (skips) | throttled/retried, not skipped |

Note: neither mechanism alone prevents *sequential* over-creation; that is handled separately by
ORB `status` listing freshly-launched instances as `pending` on the next tick, so the loop
converges instead of overshooting.

**Decision.**
Revert to `reserved_concurrent_executions = 1` for **simplicity**: it gives the same
no-two-ticks-at-once guarantee for our single (EventBridge) invoker, needs no extra resources or
code, and eliminates the stuck-lock failure mode we hit during live testing (the controller was
briefly VPC-attached, timed out, and left the lock held until its TTL expired).

**Consequences.**
- Remove `aws_dynamodb_table.lock`, its IAM statement, and the `_acquire_lock`/`_release_lock`
  logic in `ec2_capacity_controller.py`.
- An overlapping scheduled tick is throttled and async-retried (deferred re-run) rather than
  cleanly skipped - harmless at 1/min with sub-300s ticks.
- Manual concurrent invocations during testing are throttled rather than no-op'd.

**Revisit if:** the controller gains multiple legitimate concurrent invokers, ticks routinely
approach the Lambda timeout, or we need an explicit "skip" (vs retry) semantic - at which point the
DynamoDB lock (or a Step Functions state machine) becomes the better fit.
