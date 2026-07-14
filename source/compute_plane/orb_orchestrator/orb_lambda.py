"""Lambda handler: drive ORB create/status/terminate via its async SDK.

Invoked synchronously (e.g. `aws lambda invoke`) with an event of the shape:

    {"action": "create",    "template_id": "EC2Fleet-Instant-OnDemand", "count": 1}
    {"action": "status",    "request_id": "req-..."}     # request-scoped
    {"action": "status"}                                  # live managed machines
    {"action": "status",    "include_terminated": true}  # full history
    {"action": "terminate", "machine_ids": ["i-..."]}     # explicit ids
    {"action": "terminate", "all": true}                  # every LIVE machine (gated)

ORB state lives in DynamoDB. The handler is stateless: fresh ORB SDK client per invocation.

Two safety behaviours matter, since an automated controller (not just a human) drives this:

  * `status` and `terminate {"all": true}` count only LIVE machines. `list_machines()`
    returns terminated ones too, so counting them over-reports capacity and re-terminates
    dead instances; we filter out TERMINAL_MACHINE_STATES.
  * `terminate {"all": true}` bypasses graceful drain, so it's gated behind
    ORB_ALLOW_TERMINATE_ALL=1 (unset in this deployment) to prevent a stray fleet-wide kill.
"""

from __future__ import annotations

import asyncio
import logging
import os
from typing import Any

from aws_lambda_powertools import Logger

logger = Logger(service=os.environ.get("POWERTOOLS_SERVICE_NAME", "orb_orchestrator"))

# orb-py is installed unmodified; as of 1.7.0 its DynamoDB backend needs no cold-start patch.

# Terminal machine states: mirrors orb-py's MachineStatus.is_terminal. Kept as a DENYLIST
# (everything else is "live") rather than an allowlist, which had drifted and dropped
# `launching`/`stopped` — under-counting capacity and leaking them past `terminate all`.
# A denylist treats any future transient state as live: safe for both counting and the kill switch.
TERMINAL_MACHINE_STATES = {"terminated", "failed", "returned"}

# Final request states: syncing one in reconcile can't advance it and makes ORB log a
# transition ERROR, so _reconcile_requests skips them. Both cancelled spellings kept defensively.
TERMINAL_REQUEST_STATES = {"complete", "completed", "failed", "cancelled", "canceled"}


def _live_machines(machines: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Filter ORB's machine list down to live (non-terminal) machines.

    Assumes the default scheduler's wire format (lowercase `status`). HostFactory emits
    `str(enum)` ("MachineStatus.TERMINATED") instead, which this denylist never matches —
    revisit here and in the capacity controller if scheduler.type changes from default.
    """
    return [m for m in machines if m.get("status") not in TERMINAL_MACHINE_STATES]


def _enable_aws_wire_logs() -> None:
    """Opt-in (ORB_DEBUG_AWS=1): raise boto3/botocore/urllib3 to DEBUG for raw AWS wire logs.

    orb-py's setup_logging() pins those loggers to WARNING, so call this AFTER the orb client
    is opened or setup_logging clamps them back. Off by default: DEBUG is noisy (CloudWatch
    cost) and can log secrets (auth headers, payloads).
    """
    if os.environ.get("ORB_DEBUG_AWS") != "1":
        return
    for name in ("boto3", "botocore", "urllib3"):
        logging.getLogger(name).setLevel(logging.DEBUG)
    logger.warning(
        "ORB_DEBUG_AWS=1: raised boto3/botocore/urllib3 to DEBUG (verbose; may log secrets)"
    )


async def _reconcile_requests(client: Any) -> None:
    """Best-effort: refresh ORB's stored machine state from live cloud state.

    ``list_machines()`` reads a DynamoDB cache whose status only advances when ORB reconciles a
    request against live EC2 — normally driven by the capacity-controller tick. When that's
    paused, status would be stale forever and callers polling for "running" hang. So poll each
    request's status first: ``get_request_status`` does a read-through sync into the read model.

    Never raises: reconcile is best-effort, so a failure must not turn status into an error.
    """
    def _is_terminal(r: dict[str, Any]) -> bool:
        # orb-py's field name is unconfirmed: accept status or state, and sync (return False)
        # when absent/unknown so a wrong guess is a no-op, not a regression.
        st = r.get("status") or r.get("state") or ""
        return isinstance(st, str) and st.lower() in TERMINAL_REQUEST_STATES

    try:
        listed = await client.list_requests()
        with_id = [r for r in listed.get("requests", []) if r.get("request_id")]
    except Exception:  # noqa: BLE001 - reconcile is best-effort; fall back to stored state
        logger.exception("status reconcile: could not list requests; returning stored state")
        return
    # Skip terminal requests: their state can't change, so a sync is pure cost (slow + ERROR log).
    request_ids = [r["request_id"] for r in with_id if not _is_terminal(r)]
    skipped_terminal = len(with_id) - len(request_ids)
    for rid in request_ids:
        try:
            await client.get_request_status([rid])
        except Exception:  # noqa: BLE001 - skip one bad request, keep syncing the rest
            logger.warning("status reconcile: get_request_status failed", request_id=rid)
    logger.info(
        "status reconcile complete",
        requests=len(request_ids),
        skipped_terminal=skipped_terminal,
    )

# ORB needs writable work/log/cache/scripts/health dirs; env points them at /tmp (only
# writable path in Lambda). Create them before ORB initializes.
for _var in (
    "ORB_WORK_DIR",
    "ORB_LOG_DIR",
    "ORB_CACHE_DIR",
    "ORB_SCRIPTS_DIR",
    "ORB_HEALTH_DIR",
):
    _path = os.environ.get(_var)
    if _path:
        os.makedirs(_path, exist_ok=True)


def _assert_grid_config() -> None:
    """Fail loud at cold start if the DynamoDB table prefix env var is missing.

    Templates are baked into the zip at apply time (nothing to materialize at cold start).
    Region + table prefix come from orb-py's own env layer (ORB_AWS_*), which the bundled
    config.json leaves unset. We only guard table prefix: orb-py defaults it to "hostfactory",
    so an unset var would SILENTLY point ORB at the wrong tables. The Terraform module sets it.
    """
    if not os.environ.get("ORB_CONFIG_DIR"):
        return  # no bundled config dir (e.g. local test use of the baked config)

    if not os.environ.get("ORB_AWS_STORAGE__DYNAMODB__TABLE_PREFIX"):
        raise RuntimeError(
            "ORB_AWS_STORAGE__DYNAMODB__TABLE_PREFIX is unset; refusing to fall back to orb-py's "
            "'hostfactory' default table prefix. Set it (the orb_orchestrator Terraform module does)."
        )


_assert_grid_config()


class BadRequest(Exception):
    """Raised for malformed invocation payloads."""


async def _dispatch(event: dict[str, Any]) -> dict[str, Any]:
    from orb import orb  # imported lazily so cold-start dir setup runs first

    action = (event or {}).get("action")
    if action not in {"create", "status", "terminate"}:
        raise BadRequest(
            f"action must be one of create|status|terminate, got {action!r}"
        )

    async with orb(provider="aws") as client:
        # Must run after client init: setup_logging clamps the AWS loggers there.
        _enable_aws_wire_logs()
        if action == "create":
            template_id = event.get("template_id", "EC2Fleet-Instant-OnDemand")
            count = int(event.get("count", 1))
            result = await client.request_machines(
                template_id=template_id, count=count
            )
            return {"action": "create", "result": result}

        if action == "status":
            request_id = event.get("request_id")
            if request_id:
                result = await client.get_request_status([request_id])
                return {"action": "status", "result": result}
            # Refresh the read model from live cloud state before listing (see
            # _reconcile_requests), so callers polling for "running" don't see stale state.
            await _reconcile_requests(client)
            # Default to live machines for an accurate capacity count; include_terminated
            # returns the full history.
            result = await client.list_machines()
            machines = result.get("machines", [])
            if not event.get("include_terminated"):
                machines = _live_machines(machines)
            return {
                "action": "status",
                "result": {"machines": machines, "count": len(machines)},
            }

        # terminate
        if event.get("all"):
            # Fleet-wide kill switch that BYPASSES drain: gated off by default.
            if os.environ.get("ORB_ALLOW_TERMINATE_ALL") != "1":
                raise BadRequest(
                    "terminate all is disabled (set ORB_ALLOW_TERMINATE_ALL=1 to enable). "
                    "It bypasses graceful drain and must not be the scale-down path; "
                    "pass explicit machine_ids instead."
                )
            listed = await client.list_machines()
            machine_ids = [
                m["machine_id"]
                for m in _live_machines(listed.get("machines", []))
                if m.get("machine_id")
            ]
        else:
            machine_ids = event.get("machine_ids") or []
        if not machine_ids:
            raise BadRequest("terminate requires machine_ids[] or all=true")
        result = await client.return_machines(machine_ids)
        return {"action": "terminate", "requested_ids": machine_ids, "result": result}


@logger.inject_lambda_context(log_event=False)
def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Lambda entrypoint. Wraps the async ORB calls in a fresh event loop."""
    action = (event or {}).get("action")
    logger.append_keys(action=action)
    try:
        body = asyncio.run(_dispatch(event))
        logger.info("orb dispatch ok")
        return {"statusCode": 200, "body": body}
    except BadRequest as exc:
        # Client error (malformed payload / gated kill-switch): warn, do not stacktrace.
        logger.warning("bad request", error=str(exc))
        return {"statusCode": 400, "error": str(exc)}
    except Exception as exc:  # noqa: BLE001 - surface any ORB/AWS error to caller
        logger.exception("orb dispatch failed")
        return {"statusCode": 500, "error": f"{type(exc).__name__}: {exc}"}
