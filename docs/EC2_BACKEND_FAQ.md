# HTC-Grid EC2 Backend - Q&A

A short FAQ for the **EC2 worker-plane backend** and its graceful scale-down. For the full
picture see [`EC2_BACKEND_ARCHITECTURE.md`](./EC2_BACKEND_ARCHITECTURE.md), the decision log in
[`architecture_design_decisions.md`](./architecture_design_decisions.md), and the sequence
diagrams under [`diagrams/`](./diagrams) (up/down overview
[`ec2-scaling-up-sequence.md`](./diagrams/ec2-scaling-up-sequence.md), drain detail
[`ec2-scaling-down-sequence.md`](./diagrams/ec2-scaling-down-sequence.md)).

Answers cite `file:line` or the relevant ADR so they can be checked against the code.

---

## Concepts

### Q1. What does the EC2 backend add, and when do I pick it over EKS?
A single Terraform variable selects the worker plane: `worker_backend = "eks"` (default,
Helm/KEDA worker pods) or `worker_backend = "ec2"` (Agent + Lambda-RIE pairs under Docker
Compose on plain EC2, scaled by ORB). The control plane and VPC are shared and unchanged. Use
`ec2` when you want workers without an EKS cluster; the fleet is grown and drained by a
queue-watching capacity controller. See `EC2_BACKEND_ARCHITECTURE.md` §1.

### Q2. What problem does graceful scale-down solve?
Surplus instances can't just be killed - a worker may be mid-task. Scale-down is task-aware: an
instance is only terminated once it has no in-flight work (or its drain deadline passes), so
removing capacity does not abort running tasks. It is the EC2 analogue of draining a node before
the Cluster Autoscaler removes it on EKS.

### Q3. How does "cordon then sweep then terminate" work, and why span multiple ticks?
Cordon marks a surplus instance `draining` and tells its agents to stop claiming new work and
finish the current task; a later tick's **sweep** terminates it once idle. The controller never
blocks waiting for a drain - it cordons and returns, and re-derives the world next tick
(`ec2_capacity_controller.py:84` note "returns now, no blocking"). This keeps each invocation
short and crash-safe.

---

## How it decides

### Q4. How does the controller decide how much capacity it wants?
It scales in **vCPUs**, not instances (an EC2 Fleet launches a mix of instance sizes, so "number of
instances" is not a stable unit). Each tick:
`desired_pairs = ceil(backlog / TARGET_PENDING_PER_PAIR)`, then
`desired_vcpus = clamp(desired_pairs * PAIR_CPU, MIN_VCPUS, MAX_VCPUS)`.
`backlog` is read straight from the task queue - `queue_manager(...).get_queue_length()` (SQS
`ApproximateNumberOfMessages`, summed across priority queues), see
`ec2_capacity_controller._read_backlog`. Current capacity is `current_vcpus = Σ vcpus` over the
active live machines (each machine's `vcpus` comes from ORB `status`; see Q4b). It then reconciles in
three stages: sweep draining, scale up the remaining **vCPU** deficit (ORB `create` with a vCPU
target), cordon any surplus (whole instances whose summed vCPUs cover it).

### Q4b. Where does each machine's vCPU count come from, and what if it's missing?
From ORB `status` - the AWS provider derives each machine's `vcpus` into `provider_data` and the
default scheduler also surfaces it top-level, so the controller just sums it (no `DescribeInstanceTypes`
call, no extra IAM). `_vcpus_of` falls back in order: real `vcpus` → size by `memory_mib` →, if
NEITHER is present, log an **ERROR** and default to 1 worker per instance (`PAIR_CPU` vCPUs). The
fallback keeps the controller running but loses vCPU-accurate sizing, so it is surfaced loudly. (Seen
live on orb-py 1.6.2: some builds persist an empty `provider_data`, which trips this fallback; 1.7.0
is now pinned, so confirm it populates `provider_data.vcpus` on the deployed build.)

### Q5. Which instances get drained first?
Idle-first, then oldest - so the cheapest-to-remove instances go first
(`_scale_down._victim_key`, `ec2_capacity_controller.py:204-212`).

### Q6. What actually happens to a worker when it's cordoned?
The controller writes the `htc:lifecycle=draining` / `htc:drain_deadline` tags and runs
`docker compose -p htc-workers stop` over SSM (`drain.cordon`, `drain.py:77-97`). `stop` sends
SIGTERM; the agent's `GracefulKiller` catches it (`agent.py:175-194`), finishes the in-flight
task, stops claiming, then exits. The compose `stop_grace_period` (1500s,
`user-data.sh.tftpl:124,151`) bounds the wait. In a live test the **agent** containers logged
`Received SIGTERM` ~64 ms after the stop began executing and drained within ~10 s; the **RIE**
containers ignore SIGTERM, so `compose stop` rides out the full `stop_grace_period` and the SSM
command stays `InProgress` until then. The controller does not wait on it - `send_command` is
fire-and-forget and termination is gated on the worker going idle (Q10), not on the stop finishing.

---

## Busy detection & safety

### Q7. How does the controller know an instance is busy - without a new table or index?
It reuses the existing task heartbeat. `query_live_tasks` queries the same `gsi_ttl_index` the
`ttl_checker` uses, but for *live* tasks (`processing` AND `heartbeat_expiration_timestamp > now`)
instead of expired ones (`state_table_dynamodb.py:217-254`). No new index, no new table, no agent
change.

### Q8. How does a task row map back to an EC2 instance?
The worker sets each pair's owner to `<instance-id>-pair-N` (`user-data.sh.tftpl:132`,
`MY_POD_NAME`). The controller reads the projected `task_owner` and strips the `-pair-N` suffix to
recover the instance id (`drain.busy_instance_ids`, `drain.py:163`).

### Q9. What if the state table is throttling and the controller can't tell who's busy?
`busy_instance_ids` returns `None` (`drain.py:166-170`). On `None` the controller **skips
scale-down** for that tick and leaves draining instances tagged - fail-safe is to keep capacity
rather than risk killing a busy worker (`ec2_capacity_controller.py:197-200`). This is the same
throttling guard `ttl_checker` uses.

### Q10. What stops a long-running task from blocking scale-down forever?
The `htc:drain_deadline` tag, default `DRAIN_DEADLINE_SEC = 1500` (≈ the compose
`stop_grace_period`, `drain.py:43`). Past the deadline the instance is force-terminated regardless
of remaining work. A *missing/unreadable* deadline is treated as "unknown → do not terminate"
(fail-safe), so a transient `DescribeInstances` failure can't kill a draining instance
(`ec2_capacity_controller.py:134-136`).

### Q11. What happens to a task that's force-terminated past its deadline?
It's re-queued by `ttl_checker` once its heartbeat expires. Tasks are assumed idempotent in v1, so
a re-run is safe.

---

## The ORB seam

### Q12. Why route termination through ORB instead of a direct `ec2:TerminateInstances`?
So self-healing APIs don't fight the controller. If the controller bare-killed an instance under
an ASG or a Fleet in maintain-mode, the API would relaunch a replacement and ORB's bookkeeping
would drift. `orb_client.terminate(ids)` (`orb_client.py:57-61` → `orb_lambda.py:336`) lets ORB
decrement the right request's desired count. See ADR-005.

### Q13. Why is the *drain* owned by the controller but the *kill* owned by ORB?
Draining is **provider-independent**: cordon (SSM stop), idle-detect (heartbeat), and drain-state
(EC2 tags) are EC2-level and identical no matter how the instance was provisioned, so the
controller owns them (`drain.py`). Only the **kill** is API-specific, so it goes to ORB, which
picks RunInstances / EC2Fleet / ASG per request. The graceful logic stays universal; only the kill
is specialized. See ADR-005 (and ADR-004 for why an ASG can't host the lifecycle hook).

### Q14. Who is responsible for what?
The controller is the brain: read backlog, list live, read drain tags, compute the busy set,
cordon/uncordon/sweep. ORB is the hands: `list_live` / `create` / `terminate`, plus the AWS API
choice (`orb_client.py`, `orb_lambda.py`). See ADR-002.

---

## Operations & failure modes

### Q15. What guarantees only one tick runs at a time?
`reserved_concurrent_executions = 1` on the Lambda
(`capacity_controller/main.tf:131`), so EventBridge ticks (`rate(1 minute)` by default,
`main.tf:25`) never overlap. The controller is a stateless reconciler, so a crash at any point is
healed by the next tick re-converging (ADR-001).

### Q16. What if the controller crashes mid-cordon (tagged but stop never landed)?
Cordon tags *before* it stops, on purpose: a crash in between leaves a recoverable
tagged-but-not-stopped state, whereas stopped-but-not-tagged would look like idle live capacity
(`drain.cordon` docstring, `drain.py:79-83`). The sweep re-issues `compose stop` (idempotent) to
any still-busy draining instance (`drain.resend_stop`, `drain.py:100-107`) so a missed stop
self-heals instead of waiting for the deadline.

### Q17. What if backlog rebounds while instances are draining?
The sweep reclaims them instead of launching new ones: it uncordons (compose start + clear tags)
up to the size of the deficit before scale-up creates anything (`_sweep_draining`,
`ec2_capacity_controller.py:126-130`; `drain.uncordon`, `drain.py:110-121`).

### Q18. Is SSM `compose stop` reliable?
It's best-effort - SSM failures are logged, not raised (`_send_compose_command`,
`drain.py:55-74`). The `drain_deadline` tag is the backstop that guarantees eventual termination
even if a stop command never lands. Two things to know from live testing:

- **SSM `Status` is not a trustworthy receipt.** During a scale-down test a cordon came back
  `Undeliverable` on instances whose agents nonetheless logged `Received SIGTERM` ~1 s later - the
  command ran but the acknowledgement was lost. AWS reports `Undeliverable` when it can't confirm
  delivery, which is *not* the same as "did not execute". This is exactly why the controller gates
  terminate on the **effect** (worker went idle, Q10) rather than on the SSM status - an
  ack-loss false-negative can never wrongly kill a busy worker, and a truly-lost stop self-heals
  via the sweep's `resend_stop` (Q16).
- **`Undeliverable` was not reproducible on a healthy idle worker** - a clean cordon delivered and
  executed fine. The failure correlated with **rapid cordon/uncordon churn during scale events**
  (transient control-channel unavailability), not a missing VPC endpoint: the modern SSM agent
  (3.3.x) carries the whole RunCommand lifecycle over the `ssmmessages` (MGS) channel, and the
  grid VPC's existing `ssm` + `ssmmessages` interface endpoints are sufficient.

### Q19. How do I tune scale-down behavior?
Environment / Terraform knobs (all in vCPUs/pairs now): `MIN_VCPUS`, `MAX_VCPUS`,
`TARGET_PENDING_PER_PAIR`, `PAIR_CPU` (`ec2_capacity_controller.py`), `DRAIN_DEADLINE_SEC`
(`drain.py:43`), and the tick rate (`capacity_controller/main.tf`). The grid-config inputs that map
to these are `orb_min_vcpus` / `orb_max_vcpus` / `orb_target_pending_per_pair` / `ec2_worker_vcpus` /
`ec2_drain_deadline_sec` / `orb_control_interval`. See the deployment guide for the full table.

### Q20. Why is `terminate {"all": true}` disabled by default in ORB?
It's a fleet-wide kill switch that **bypasses** the graceful drain path, so it's gated behind
`ORB_ALLOW_TERMINATE_ALL=1` and left unset in the HTC-Grid deployment - a stray invocation can't
wipe a live fleet mid-task. The scale-down path always passes explicit `machine_ids`
(`orb_lambda.py:333-336`).
