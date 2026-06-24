"""Lambda handler: drive ORB create/status/terminate via its async SDK.

Invoked synchronously (e.g. `aws lambda invoke`) with an event of the shape:

    {"action": "create",    "template_id": "EC2Fleet-Instant-OnDemand", "count": 1}
    {"action": "status",    "request_id": "req-..."}     # request-scoped
    {"action": "status"}                                  # live managed machines
    {"action": "status",    "include_terminated": true}  # full history
    {"action": "terminate", "machine_ids": ["i-..."]}     # explicit ids
    {"action": "terminate", "all": true}                  # every LIVE machine (gated)

ORB state lives in DynamoDB (tables created/used per the bundled config). The
handler is stateless: it opens a fresh ORB SDK client per invocation.

Two safety behaviours matter for the HTC-Grid integration, where an automated
controller (not just a human operator) drives this handler:

  * `status` and `terminate {"all": true}` count only LIVE machines by default.
    ORB's `list_machines()` returns every machine it ever managed, including
    terminated ones, so a naive "count machines" over-reports capacity and a
    naive "terminate all" re-issues terminate against already-dead instances.
    We filter to LIVE_STATES so the controller reasons over real capacity.
  * `terminate {"all": true}` is a fleet-wide kill switch that BYPASSES the
    graceful drain path. It is gated behind ORB_ALLOW_TERMINATE_ALL=1, left
    unset in the HTC-Grid deployment, so a stray invocation cannot wipe a live
    worker fleet mid-task.
"""

from __future__ import annotations

import asyncio
import logging
import os
from typing import Any

from aws_lambda_powertools import Logger

logger = Logger(service=os.environ.get("POWERTOOLS_SERVICE_NAME", "orb_orchestrator"))

# orb-py is installed unmodified by `pip_requirements` (its native wheels match the runtime).
# As of orb-py 1.7.0 the DynamoDB storage backend works out of the box, so there is no
# cold-start monkey-patch step anymore (earlier builds copied orb -> /tmp and applied 4
# DynamoDB fixes; those are now upstream).

# Machine statuses that count as live capacity. ORB persists terminated machines
# in its state table, so anything outside this set is historical and must not be
# counted as capacity or re-terminated.
LIVE_STATES = {"pending", "running", "stopping", "shutting-down"}

# Request states that are final. get_request_status can never advance these, so syncing one
# during reconcile just wastes a slow round-trip and makes ORB log a transition ERROR
# ("Cannot transition request from failed to complete"). Skip them in _reconcile_requests.
# Both spellings of cancelled are included since the exact orb-py value is unconfirmed.
TERMINAL_REQUEST_STATES = {"complete", "completed", "failed", "cancelled", "canceled"}


def _live_machines(machines: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Filter ORB's machine list down to live (non-terminated) machines."""
    return [m for m in machines if m.get("status") in LIVE_STATES]


def _enable_aws_wire_logs() -> None:
    """Opt-in: surface botocore's raw AWS request/response DEBUG logs to CloudWatch.

    orb-py's setup_logging() (run during orb() client init) hard-pins boto3/botocore/urllib3
    to WARNING, so even with orb at DEBUG the raw AWS wire dumps never reach the handlers.
    When ORB_DEBUG_AWS=1, re-raise those loggers to DEBUG. Call this AFTER the orb client is
    opened, otherwise setup_logging runs later and clamps them back to WARNING.

    Off by default on purpose: botocore DEBUG is very noisy (every header + full response
    body -> CloudWatch volume/cost) and can log sensitive data (auth headers, payloads).
    Use it for a targeted debug run, then unset the env var.
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

    ``list_machines()`` reads DynamoDB, which is a cache of provider state. The stored
    machine status only advances (pending->running) when ORB reconciles a request against
    live EC2. Normally the capacity-controller tick drives that; when the tick is paused
    (e.g. the manual submit script disables it so it can't reap the worker mid-test),
    ``status`` would report stale state forever and callers polling for "running" hang.

    So before reading machines, enumerate ORB's requests and poll each one's status.
    ``get_request_status`` performs a read-through sync (fetch live provider machines ->
    reconcile -> persist refreshed status to DynamoDB), so this pulls reality into the read
    model before we read it.

    Never raises: a sync failure must not turn a status call into an error. The capacity
    controller calls status every tick and must keep working even if reconcile fails.
    """
    def _is_terminal(r: dict[str, Any]) -> bool:
        # Read defensively: orb-py's exact field name/values are unconfirmed, so accept either
        # status/state and fall back to syncing (return False) when absent/unknown. A wrong guess
        # is then a no-op, not a regression.
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

# ORB wants writable work/log/cache/scripts/health dirs. In Lambda only /tmp is
# writable, so the env points there (see CDK / Dockerfile); ensure they exist
# before ORB initializes.
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
    """Assert the grid's DynamoDB table prefix is set; the templates are baked at deploy time.

    The orb_orchestrator Terraform module now RENDERS a grid-complete aws_templates.json at apply
    time (subnet / SG / instance-profile / AMI / user_data + the EC2Fleet vCPU-unit native spec all
    filled in) and bakes it into the zip under /var/task/orb-config. So there is nothing to
    materialize at cold start — ORB reads the bundled, read-only config directly (ORB_CONFIG_DIR
    stays /var/task/orb-config; ORB only ever reads the templates on the create/status/terminate
    path, never writes them).

    Region + DynamoDB table prefix are still driven by ORB's OWN env-var layer: orb-py's
    AWSProviderConfig is a pydantic-settings BaseSettings (env_prefix="ORB_AWS_",
    env_nested_delimiter="__"), so it reads ORB_AWS_REGION and ORB_AWS_STORAGE__DYNAMODB__* directly
    and the bundled config.json deliberately leaves those unset.

    We only fail loud if the table prefix is missing: orb-py's DynamodbStrategyConfig defaults
    table_prefix to "hostfactory", so an unset env var would SILENTLY point ORB at the wrong (or
    non-existent) tables. In the Terraform deployment the module always sets it.
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
        # orb's setup_logging (run during client init above) clamps the AWS SDK loggers to
        # WARNING; re-raise them here if ORB_DEBUG_AWS=1 so raw wire logs reach CloudWatch.
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
            # Refresh the read model from live cloud state before listing, so callers
            # (e.g. a submit script polling for "running") don't see stale DynamoDB state
            # when the capacity-controller tick that normally drives reconcile is paused.
            await _reconcile_requests(client)
            # Machine list. Default to live machines only so a controller's
            # capacity count is accurate; include_terminated=true returns the
            # full history.
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
