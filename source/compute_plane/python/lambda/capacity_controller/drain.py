# Copyright 2024 Amazon.com, Inc. or its affiliates.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

"""Provider-independent drain core for the EC2 capacity controller (ADR-005).

Draining is EC2-level and identical no matter how an instance was provisioned (ORB
RunInstances / EC2Fleet / ASG). It is owned by the controller, not the capacity API:

  * cordon(ids)        -> tag instances `draining` (+ drain_deadline) and SSM `compose stop`
                          so each agent's SIGTERM handler finishes its in-flight task and
                          stops claiming new ones.
  * uncordon(ids)      -> SSM `compose start` and clear the tags (reclaim a draining instance).
  * read_drain_state() -> read the htc:* tags back via DescribeInstances.
  * busy_instance_ids()-> instances with a live task RIGHT NOW, from the task heartbeat
                          (the live mirror of ttl_checker's gsi_ttl_index query).

The actual termination is NOT here: it goes through ORB (orb_client.py) so self-healing APIs
(ASG / Fleet maintain-mode) decrement desired instead of relaunching.
"""

from __future__ import annotations

import os
import time

import boto3
from aws_lambda_powertools import Logger

from utils.state_table_common import StateTableException

logger = Logger(service=os.environ.get("POWERTOOLS_SERVICE_NAME", "capacity_controller"))

# Drain-state EC2 tags written on a worker when it is cordoned. drain_deadline bounds the
# drain: past it the instance is force-terminated regardless of remaining work (stragglers
# re-queued by ttl_checker).
TAG_LIFECYCLE = "htc:lifecycle"
TAG_DRAIN_DEADLINE = "htc:drain_deadline"
LIFECYCLE_DRAINING = "draining"

# Seconds a cordoned instance may finish in-flight work before it is force-terminated.
# Defaults to the worker compose stop_grace_period (1500s) so a clean drain normally completes.
DRAIN_DEADLINE_SEC = int(os.environ.get("DRAIN_DEADLINE_SEC", "1500"))

# Stop / start the worker compose project. `stop` SIGTERMs the agents (GracefulKiller finishes
# the in-flight task then stops claiming); `start` resumes them. Project name matches user-data.
_COMPOSE_STOP_CMD = "docker compose -p htc-workers stop"
_COMPOSE_START_CMD = "docker compose -p htc-workers start"

_REGION = os.environ["REGION"]
_ec2 = boto3.client("ec2", region_name=_REGION)
_ssm = boto3.client("ssm", region_name=_REGION)


def _send_compose_command(machine_ids: list[str], command: str) -> dict:
    """Run a shell command on the given instances over SSM (best-effort).

    SSM failures are logged, not raised: a missed stop must not fail the tick. The drain
    deadline still forces termination, and the sweep re-issues stop while the instance is
    still busy (ADR-005 crash-recovery), so a transient miss self-heals.
    """
    ids = [m for m in machine_ids if m]
    if not ids:
        return {}
    try:
        resp = _ssm.send_command(
            InstanceIds=ids,
            DocumentName="AWS-RunShellScript",
            Parameters={"commands": [command]},
        )
        return {"command_id": resp.get("Command", {}).get("CommandId")}
    except Exception as exc:  # noqa: BLE001
        logger.exception("SSM send_command failed", command=command, machine_ids=ids)
        return {"error": str(exc)}


def cordon(machine_ids: list[str]) -> dict:
    """Mark instances draining and tell them to stop claiming (finish in-flight work).

    Tag BEFORE stop on purpose: a crash between the two leaves a recoverable
    tagged-but-not-stopped state (the sweep re-issues stop), whereas stopped-but-not-tagged
    would look like idle live capacity.
    """
    ids = [m for m in machine_ids if m]
    if not ids:
        return {}
    deadline = int(time.time()) + DRAIN_DEADLINE_SEC
    _ec2.create_tags(
        Resources=ids,
        Tags=[
            {"Key": TAG_LIFECYCLE, "Value": LIFECYCLE_DRAINING},
            {"Key": TAG_DRAIN_DEADLINE, "Value": str(deadline)},
        ],
    )
    ssm = _send_compose_command(ids, _COMPOSE_STOP_CMD)
    logger.info("cordon", machine_ids=ids, drain_deadline=deadline)
    return {"machine_ids": ids, "drain_deadline": deadline, "ssm": ssm}


def resend_stop(machine_ids: list[str]) -> dict:
    """Re-issue `compose stop` to already-draining instances (idempotent).

    Heals the cordon crash-window: if CreateTags succeeded but the original stop never landed,
    the instance is tagged draining but still claiming; the sweep calls this so the stop is
    retried instead of waiting for the deadline (ADR-005).
    """
    return _send_compose_command(machine_ids, _COMPOSE_STOP_CMD)


def uncordon(machine_ids: list[str]) -> dict:
    """Resume a draining instance and clear its drain tags (reclaim on backlog rebound)."""
    ids = [m for m in machine_ids if m]
    if not ids:
        return {}
    ssm = _send_compose_command(ids, _COMPOSE_START_CMD)
    _ec2.delete_tags(
        Resources=ids,
        Tags=[{"Key": TAG_LIFECYCLE}, {"Key": TAG_DRAIN_DEADLINE}],
    )
    logger.info("uncordon", machine_ids=ids)
    return {"machine_ids": ids, "ssm": ssm}


def read_drain_state(machine_ids: list[str]) -> dict[str, dict]:
    """Return {instance_id: {lifecycle, drain_deadline}} from the htc:* EC2 tags.

    Best-effort: on a DescribeInstances error returns an empty mapping. Callers MUST treat a
    missing drain_deadline as "unknown -> do not force-terminate" (fail-safe), not as 0.
    """
    ids = [m for m in machine_ids if m]
    if not ids:
        return {}
    try:
        resp = _ec2.describe_instances(InstanceIds=ids)
    except Exception:  # noqa: BLE001
        logger.exception("describe_instances for drain tags failed", machine_ids=ids)
        return {}
    out: dict[str, dict] = {}
    for reservation in resp.get("Reservations", []):
        for inst in reservation.get("Instances", []):
            iid = inst.get("InstanceId")
            tags = {t["Key"]: t["Value"] for t in inst.get("Tags", [])}
            if iid:
                out[iid] = {
                    "lifecycle": tags.get(TAG_LIFECYCLE),
                    "drain_deadline": tags.get(TAG_DRAIN_DEADLINE),
                }
    return out


def busy_instance_ids(state_table) -> set[str] | None:
    """EC2 instance ids with at least one in-flight task right now.

    Reads the live-task heartbeat (processing* AND heartbeat_expiration_timestamp > now) and
    maps each task_owner "<instance-id>-pair-N" back to its instance. Returns None if the state
    table is throttling, so the caller defers scale-down (fail safe = keep capacity).
    """
    busy: set[str] = set()
    try:
        for live_tasks in state_table.query_live_tasks():
            for item in live_tasks:
                owner = item.get("task_owner") or ""
                instance_id = owner.split("-pair-")[0]
                if instance_id and instance_id != "None":
                    busy.add(instance_id)
    except StateTableException as exc:
        if getattr(exc, "caused_by_throttling", False):
            logger.warning("state table throttling: deferring scale-down this tick")
            return None
        raise
    return busy
