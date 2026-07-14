# Copyright 2024 Amazon.com, Inc. or its affiliates.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

"""HTC-Grid EC2 capacity controller.

EventBridge invokes this on a fixed interval. Each tick it:
  1. reads the backlog directly from the task queue (SQS ApproximateNumberOfMessages);
  2. reads live capacity from ORB (orb_client.list_live) + drain tags from EC2;
  3. computes a desired vCPU target = clamp(ceil(backlog / target_per_pair) * PAIR_CPU, MIN, MAX),
     where each live machine's vCPUs come straight from ORB status (provider_data.vcpus);
  4. reconciles: sweep draining instances, scale up (orb_client.create a vCPU deficit), or scale
     down (cordon whole instances whose summed vCPUs cover the surplus).

Capacity is counted in vCPUs, not instances: ORB launches an EC2 Fleet with
TargetCapacityUnitType=vcpu, so the create count is a vCPU target and a heterogeneous mix of
instance types is handled correctly (each instance auto-packs floor(vCPU / PAIR_CPU) pairs).

Two responsibilities, two homes (ADR-005):
  * DRAIN is EC2-level and owned HERE (drain.py): cordon = SSM `compose stop` + `draining`
    tags; idle-detect = the task heartbeat; sweep = terminate-when-idle/expired or uncordon.
    EC2-level, so it works no matter which AWS API provisioned the instance.
  * The KILL goes through ORB (orb_client.terminate): ORB decrements the right request's desired
    count for self-healing APIs (ASG / Fleet maintain) instead of letting a replacement relaunch.
    ORB is the capacity abstraction — it picks RunInstances / EC2Fleet / ASG per request; the
    controller just hands it the idle ids.

The controller is a STATELESS RECONCILER: it keeps no state between ticks and re-derives the
world each tick from observed truth (orb_client.list_live, EC2 drain tags, the heartbeat busy
set). With reserved_concurrent_executions = 1 (ADR-001) ticks never overlap, so a crash at a
random point is healed by the next tick re-converging. Cordon's tag-then-stop is non-atomic, so
the sweep RE-ISSUES `compose stop` to any still-busy draining instance (ADR-005 crash-recovery).
"""

from __future__ import annotations

import math
import os
import time

from aws_lambda_powertools import Logger

from api.queue_manager import queue_manager
from api.state_table_manager import state_table_manager

import drain
import orb_client

logger = Logger(service=os.environ.get("POWERTOOLS_SERVICE_NAME", "capacity_controller"))

REGION = os.environ["REGION"]
# The controller scales in vCPUs (EC2 Fleet TargetCapacityUnitType=vcpu). A pair needs PAIR_CPU
# vCPUs, ORB's create count is a vCPU target, and AWS packs instances until the target is met;
# each instance then auto-packs floor(vCPU / PAIR_CPU) pairs at boot. Counting in vCPUs (not
# instances) is what makes a heterogeneous fleet's capacity math correct (replaces the old 1
# worker-per-instance assumption).
PAIR_CPU = max(1, int(os.environ.get("PAIR_CPU", "1")))
# MiB per pair — only used as a fallback to size a machine by memory when ORB status has no vcpus.
PAIR_MEMORY = max(1, int(os.environ.get("PAIR_MEMORY", "2048")))
MIN_VCPUS = int(os.environ.get("MIN_VCPUS", "0"))
MAX_VCPUS = int(os.environ.get("MAX_VCPUS", "64"))
TARGET_PER_PAIR = max(1, int(os.environ.get("TARGET_PENDING_PER_PAIR", "4")))

# Task queue, read directly for the backlog (SQS ApproximateNumberOfMessages). This is the
# same number scaling_metrics used to republish to CloudWatch — read here without the hop.
TASK_QUEUE_SERVICE = os.environ["TASK_QUEUE_SERVICE"]
TASK_QUEUE_CONFIG = os.environ.get("TASK_QUEUE_CONFIG", "{}")
TASKS_QUEUE_NAME = os.environ["TASKS_QUEUE_NAME"]

# State table, used to detect which workers are busy (heartbeat-based, same as ttl_checker).
STATE_TABLE_NAME = os.environ["STATE_TABLE_NAME"]
STATE_TABLE_SERVICE = os.environ.get("STATE_TABLE_SERVICE", "DynamoDB")
STATE_TABLE_CONFIG = os.environ.get("STATE_TABLE_CONFIG", "{}")

task_queue = queue_manager(
    TASK_QUEUE_SERVICE, TASK_QUEUE_CONFIG, TASKS_QUEUE_NAME, REGION
)
state_table = state_table_manager(
    STATE_TABLE_SERVICE, STATE_TABLE_CONFIG, STATE_TABLE_NAME, REGION
)


def _read_backlog() -> float:
    """Pending tasks, read straight from the task queue (SQS ApproximateNumberOfMessages).

    For PrioritySQS, queue_manager returns QueuePrioritySQS whose get_queue_length() sums
    the backlog across every priority queue, so this works unchanged for both backends.
    """
    return float(task_queue.get_queue_length())


def _machine_age_key(m: dict):
    """Oldest-first sort key: machines carry a created timestamp; fall back to id."""
    return m.get("created_at") or m.get("launch_time") or m.get("machine_id", "")


def _machine_field_int(m: dict, key: str) -> int | None:
    """Read an int field from an ORB status machine, top-level first then provider_data.

    ORB's default scheduler surfaces capacity fields (e.g. vcpus) both at the top level and inside
    provider_data; returns None when absent or non-numeric.
    """
    v = m.get(key)
    if v is None:
        v = (m.get("provider_data") or {}).get(key)
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


def _vcpus_of(m: dict) -> int:
    """Per-machine vCPU capacity for the controller's vCPU-unit accounting.

    Read from ORB status (`vcpus`). ORB's AWS provider is supposed to derive and persist each
    machine's vCPU count, but some orb-py builds persist an EMPTY provider_data, so the field can be
    missing in practice. Fallback order:
      1. real `vcpus` from status -> use it;
      2. no vCPUs but `memory_mib` known -> size by memory, expressed back in vCPUs;
      3. NEITHER vcpu nor memory data -> log an ERROR and default to the legacy "1 worker == 1
         instance" mapping, counting the instance as exactly one pair (PAIR_CPU vCPUs). This keeps
         the controller running (no crash, no zero-capacity) but loses vCPU-accurate sizing, so it
         is surfaced at ERROR level rather than silently.
    """
    vcpus = _machine_field_int(m, "vcpus")
    if vcpus and vcpus > 0:
        return vcpus

    mem_mib = _machine_field_int(m, "memory_mib")
    if mem_mib and mem_mib > 0:
        logger.error(
            "machine missing vcpus in ORB status; sized from memory_mib instead "
            "(check orb-py populates provider_data.vcpus)",
            machine_id=m.get("machine_id"),
            instance_type=m.get("instance_type"),
            memory_mib=mem_mib,
        )
        return max(1, mem_mib // PAIR_MEMORY) * PAIR_CPU

    logger.error(
        "machine has no vcpu or memory data in ORB status; defaulting to 1 worker per instance "
        "(vCPU-accurate scaling degraded - check orb-py populates provider_data.vcpus)",
        machine_id=m.get("machine_id"),
        instance_type=m.get("instance_type"),
    )
    return PAIR_CPU


def _pairs_of(m: dict) -> int:
    """Pairs a machine runs = floor(vCPUs / PAIR_CPU); mirrors the boot-time auto-pack CPU half."""
    return max(1, _vcpus_of(m) // PAIR_CPU)


def _sweep_draining(draining, deficit_vcpus, busy, now, actions):
    """Stage 1 — sweep draining instances: reclaim, terminate-when-safe, or re-stop.

    For each draining instance (oldest first):
      * deficit_vcpus > 0 -> uncordon (reclaim instead of launching new); consumes this instance's
                             vCPUs from the deficit.
      * drained / past deadline -> terminate via ORB.
      * still busy    -> re-issue compose stop (idempotent) to heal a cordon whose original stop
                         never landed (ADR-005 crash-recovery).
      * busy unknown (throttling) and not past deadline -> leave for a later tick.

    Returns the vCPU deficit remaining after any uncordons (input for the scale-up stage).
    """
    logger.debug(
        "stage sweep: begin",
        draining=len(draining),
        deficit_vcpus_in=deficit_vcpus,
        busy_known=busy is not None,
    )
    to_uncordon: list[str] = []
    to_terminate: list[str] = []
    to_resend_stop: list[str] = []
    for m in sorted(draining, key=_machine_age_key):
        iid = m.get("machine_id")
        if not iid:
            continue
        if deficit_vcpus > 0:
            # Backlog rebounded: reclaim a draining instance instead of launching a new one.
            to_uncordon.append(iid)
            deficit_vcpus -= _vcpus_of(m)
            logger.debug("stage sweep: reclaim draining instance", machine_id=iid, deficit_vcpus_left=deficit_vcpus)
            continue
        # Fail-safe deadline: a missing/unreadable drain_deadline tag means "unknown", so we
        # do NOT force-terminate this tick (a transient DescribeInstances failure must not kill
        # draining instances mid-task). Only a real, past deadline forces termination.
        raw_deadline = m.get("drain_deadline")
        deadline_passed = raw_deadline is not None and now >= int(raw_deadline)
        is_busy = busy is not None and iid in busy
        drained = busy is not None and not is_busy
        logger.debug(
            "stage sweep: evaluate draining instance",
            machine_id=iid,
            drain_deadline=raw_deadline,
            deadline_passed=deadline_passed,
            is_busy=is_busy,
            drained=drained,
        )
        if drained or deadline_passed:
            to_terminate.append(iid)
        elif is_busy:
            # Still busy: re-issue compose stop (idempotent) to heal a cordon that tagged the
            # instance but whose original stop never landed (ADR-005 crash-recovery).
            to_resend_stop.append(iid)
        # else: busy unknown (throttling) and not past deadline -> leave it for a later tick.

    if to_uncordon:
        drain.uncordon(to_uncordon)
        actions.append({"action": "uncordon", "machine_ids": to_uncordon})
    if to_resend_stop:
        drain.resend_stop(to_resend_stop)
        actions.append({"action": "resend_stop", "machine_ids": to_resend_stop})
    if to_terminate:
        res = orb_client.terminate(to_terminate)
        actions.append({"action": "terminate", "machine_ids": to_terminate, "orb": res})

    logger.debug(
        "stage sweep: done",
        uncordon=len(to_uncordon),
        resend_stop=len(to_resend_stop),
        terminate=len(to_terminate),
        deficit_vcpus_out=deficit_vcpus,
    )
    return deficit_vcpus


def _scale_up(deficit_vcpus, actions):
    """Stage 2 — scale up: any vCPU deficit left after reclaiming draining instances -> create.

    ORB's create count is a vCPU target (EC2 Fleet TargetCapacityUnitType=vcpu); AWS packs
    instances until the target is met, so a small last-instance overshoot is expected and
    self-corrects on the next tick.
    """
    logger.debug("stage scale_up: begin", deficit_vcpus=deficit_vcpus)
    if deficit_vcpus > 0:
        res = orb_client.create(deficit_vcpus)
        actions.append({"action": "create", "vcpus": deficit_vcpus, "orb": res})
        logger.debug("stage scale_up: requested capacity", vcpus=deficit_vcpus)
    else:
        logger.debug("stage scale_up: no deficit, skip")


def _scale_down(active, current_vcpus, desired_vcpus, busy, actions):
    """Stage 3 — scale down: cordon whole active instances whose summed vCPUs cover the surplus.

    Cordon is non-destructive (the worker finishes its in-flight task then stops); the next tick's
    sweep terminates it once idle. Victim order is idle-first then oldest, so we drain the cheapest
    first; we cordon whole instances until their combined vCPUs cover the surplus (a partial last
    instance is left running rather than over-draining).
    """
    surplus_vcpus = current_vcpus - desired_vcpus
    logger.debug("stage scale_down: begin", current_vcpus=current_vcpus, desired_vcpus=desired_vcpus, surplus_vcpus=surplus_vcpus, busy_known=busy is not None)
    if surplus_vcpus <= 0:
        logger.debug("stage scale_down: no surplus, skip")
        return
    if busy is None:
        # Throttling: cannot tell which instances are idle. Defer cordoning to keep
        # capacity rather than risk draining a busy worker.
        logger.warning("surplus but busy-set unknown (throttling); skipping cordon", surplus_vcpus=surplus_vcpus)
        return

    # Victim order: idle instances first, then oldest, so we drain the cheapest first.
    def _victim_key(m: dict):
        iid = m.get("machine_id", "")
        return (1 if iid in busy else 0, _machine_age_key(m))

    victims: list[str] = []
    removed_vcpus = 0
    for m in sorted(active, key=_victim_key):
        if removed_vcpus >= surplus_vcpus:
            break
        iid = m.get("machine_id")
        if not iid:
            continue
        victims.append(iid)
        removed_vcpus += _vcpus_of(m)
    logger.debug("stage scale_down: selected victims", victims=victims, count=len(victims), removed_vcpus=removed_vcpus)
    if victims:
        drain.cordon(victims)
        actions.append({"action": "cordon", "machine_ids": victims, "vcpus": removed_vcpus})


@logger.inject_lambda_context(log_event=False)
def handler(event, context):  # noqa: ANN001
    # Single-flight is guaranteed by reserved_concurrent_executions = 1 (ADR-001).
    now = int(time.time())
    backlog = _read_backlog()
    machines = orb_client.list_live()
    live = len(machines)

    # Drain state is controller-owned EC2 tags, read directly (not via the provider).
    drain_state = drain.read_drain_state([m.get("machine_id") for m in machines])
    for m in machines:
        st = drain_state.get(m.get("machine_id"), {})
        m["lifecycle"] = st.get("lifecycle")
        m["drain_deadline"] = st.get("drain_deadline")

    draining = [m for m in machines if m.get("lifecycle") == drain.LIFECYCLE_DRAINING]
    active = [m for m in machines if m.get("lifecycle") != drain.LIFECYCLE_DRAINING]

    # Demand and capacity are both in vCPUs. desired_pairs from backlog -> vCPU target; current
    # capacity = sum of each active machine's real vCPUs (from ORB status). This makes a
    # heterogeneous fleet's math correct: a big instance counts for proportionally more.
    desired_pairs = math.ceil(backlog / TARGET_PER_PAIR) if backlog > 0 else 0
    desired_vcpus = desired_pairs * PAIR_CPU
    desired_vcpus = max(MIN_VCPUS, min(MAX_VCPUS, desired_vcpus))
    current_vcpus = sum(_vcpus_of(m) for m in active)

    busy = drain.busy_instance_ids(state_table)  # None if state table is throttling

    logger.info(
        "capacity reconcile",
        backlog=backlog,
        live=live,
        active=len(active),
        draining=len(draining),
        target_per_pair=TARGET_PER_PAIR,
        pair_cpu=PAIR_CPU,
        desired_pairs=desired_pairs,
        desired_vcpus=desired_vcpus,
        current_vcpus=current_vcpus,
        min_vcpus=MIN_VCPUS,
        max_vcpus=MAX_VCPUS,
        busy_known=busy is not None,
    )

    actions: list[dict] = []
    deficit_vcpus = desired_vcpus - current_vcpus  # >0 need more capacity; surplus handled separately

    # The three reconcile stages (ADR-005). Sweep returns the vCPU deficit left after reclaiming
    # draining instances, which scale-up then satisfies; scale-down handles surplus.
    deficit_vcpus = _sweep_draining(draining, deficit_vcpus, busy, now, actions)
    _scale_up(deficit_vcpus, actions)
    _scale_down(active, current_vcpus, desired_vcpus, busy, actions)

    if not actions:
        logger.info("noop", live=live, desired_vcpus=desired_vcpus, current_vcpus=current_vcpus)
        return {"statusCode": 200, "action": "noop", "live": live, "desired_vcpus": desired_vcpus, "current_vcpus": current_vcpus}
    logger.info("reconcile actions", action_count=len(actions))
    return {"statusCode": 200, "actions": actions, "live": live, "desired_vcpus": desired_vcpus, "current_vcpus": current_vcpus}
