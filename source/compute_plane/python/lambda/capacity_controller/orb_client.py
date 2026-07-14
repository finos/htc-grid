# Copyright 2024 Amazon.com, Inc. or its affiliates.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

"""Thin client for the ORB orchestrator Lambda.

The controller owns draining (cordon / idle-detect / sweep, see drain.py) and talks to ORB
only for capacity bookkeeping: list what is live, add capacity, remove specific instances.
ORB is the capacity abstraction — it decides which AWS API (RunInstances / EC2Fleet / ASG,
possibly different per request) actually provisions and removes the instances. The controller
does not know or care which; it just hands ORB the idle ids to terminate.

`terminate` routes through ORB (not a bare ec2:TerminateInstances) so ORB decrements the right
request's desired count for self-healing APIs (ASG / Fleet maintain-mode) instead of letting a
replacement relaunch.
"""

from __future__ import annotations

import json
import os

import boto3
from aws_lambda_powertools import Logger

logger = Logger(service=os.environ.get("POWERTOOLS_SERVICE_NAME", "capacity_controller"))

REGION = os.environ["REGION"]
ORCHESTRATOR_FUNCTION = os.environ["ORCHESTRATOR_FUNCTION_NAME"]
TEMPLATE_ID = os.environ.get("ORB_TEMPLATE_ID", "EC2Fleet-Instant-OnDemand")

_lambda = boto3.client("lambda", region_name=REGION)


def _invoke(payload: dict) -> dict:
    resp = _lambda.invoke(
        FunctionName=ORCHESTRATOR_FUNCTION,
        InvocationType="RequestResponse",
        Payload=json.dumps(payload).encode(),
    )
    return json.loads(resp["Payload"].read() or b"{}")


def list_live() -> list[dict]:
    """Live (non-terminated) machines ORB manages.

    Each machine dict carries at least 'machine_id', 'instance_type', and 'vcpus' (the default
    scheduler surfaces vcpus at the top level and inside 'provider_data'); the controller sums
    'vcpus' to measure capacity.
    """
    body = _invoke({"action": "status"})
    return body.get("body", {}).get("result", {}).get("machines", [])


def create(count: int) -> dict:
    """Ask ORB to add `count` units of capacity.

    For the EC2 Fleet template (TargetCapacityUnitType=vcpu) `count` is a vCPU target:
    ORB sets TotalTargetCapacity=count and AWS packs instances until their summed vCPUs meet it.
    """
    res = _invoke({"action": "create", "template_id": TEMPLATE_ID, "count": count})
    logger.info("orb.create", count=count, template_id=TEMPLATE_ID)
    return res


def terminate(machine_ids: list[str]) -> dict:
    """Ask ORB to terminate these specific (already-drained) instances."""
    res = _invoke({"action": "terminate", "machine_ids": machine_ids})
    logger.info("orb.terminate", machine_ids=machine_ids, count=len(machine_ids))
    return res
