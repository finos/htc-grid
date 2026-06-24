# Copyright 2024 Amazon.com, Inc. or its affiliates.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

"""Unit tests for the ORB orchestrator Lambda's status reconcile path.

Runnable with plain stdlib (no pytest): `python3 -m unittest test_orb_lambda`.
The handler imports aws_lambda_powertools at module load and `orb` lazily inside _dispatch;
neither is installed in dev, so we stub them in sys.modules before importing.
"""

from __future__ import annotations

import asyncio
import os
import sys
import types
import unittest
from unittest import mock


def _install_stub_modules() -> None:
    """Stub the deps the handler imports at module load so it can import in dev."""
    if "aws_lambda_powertools" not in sys.modules:
        powertools = types.ModuleType("aws_lambda_powertools")

        class _Logger:
            def __init__(self, *a, **k):
                pass

            def append_keys(self, **k):
                pass

            def info(self, *a, **k):
                pass

            def warning(self, *a, **k):
                pass

            def exception(self, *a, **k):
                pass

            def inject_lambda_context(self, *a, **k):
                # Used as @logger.inject_lambda_context(log_event=False): return a
                # decorator that hands the wrapped function back unchanged.
                def _decorator(func):
                    return func

                return _decorator

        powertools.Logger = _Logger
        sys.modules["aws_lambda_powertools"] = powertools


os.environ.pop("ORB_CONFIG_DIR", None)  # skip the _assert_grid_config table-prefix check at import
_install_stub_modules()

# Import the module under test after the stubs are in place.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import orb_lambda  # noqa: E402


class FakeClient:
    """Records call order; configurable failures for the reconcile methods."""

    def __init__(self, requests, machines, *, fail_list=False, fail_status_for=()):
        self._requests = requests
        self._machines = machines
        self._fail_list = fail_list
        self._fail_status_for = set(fail_status_for)
        self.calls: list[tuple] = []

    async def list_requests(self, **kwargs):
        self.calls.append(("list_requests",))
        if self._fail_list:
            raise RuntimeError("boom: list_requests")
        return {"requests": self._requests}

    async def get_request_status(self, request_ids, **kwargs):
        self.calls.append(("get_request_status", tuple(request_ids)))
        if set(request_ids) & self._fail_status_for:
            raise RuntimeError("boom: get_request_status")
        return {"requests": []}

    async def list_machines(self, **kwargs):
        self.calls.append(("list_machines",))
        return {"machines": self._machines}

    async def request_machines(self, template_id, count, **kwargs):
        self.calls.append(("request_machines", template_id, count))
        return {"request_id": "req-new"}

    async def return_machines(self, machine_ids, **kwargs):
        self.calls.append(("return_machines", tuple(machine_ids)))
        return {"status": "ok"}


def _patch_orb(client):
    """Patch `from orb import orb` so _dispatch gets `client` from the async CM."""

    class _CM:
        async def __aenter__(self):
            return client

        async def __aexit__(self, *exc):
            return False

    def _orb(provider=None):
        return _CM()

    orb_pkg = types.ModuleType("orb")
    orb_pkg.orb = _orb
    return mock.patch.dict(sys.modules, {"orb": orb_pkg})


class StatusReconcileTests(unittest.TestCase):
    def test_plain_status_lists_then_syncs_each_then_lists_machines(self):
        client = FakeClient(
            requests=[{"request_id": "req-1"}, {"request_id": "req-2"}],
            machines=[
                {"machine_id": "i-1", "status": "running"},
                {"machine_id": "i-2", "status": "terminated"},  # filtered out (not LIVE)
            ],
        )
        with _patch_orb(client):
            out = asyncio.run(orb_lambda._dispatch({"action": "status"}))

        # Order: list_requests -> get_request_status per request -> list_machines.
        self.assertEqual(
            client.calls,
            [
                ("list_requests",),
                ("get_request_status", ("req-1",)),
                ("get_request_status", ("req-2",)),
                ("list_machines",),
            ],
        )
        # Live filter applied: terminated machine dropped.
        self.assertEqual(out["result"]["count"], 1)
        self.assertEqual(out["result"]["machines"][0]["machine_id"], "i-1")

    def test_list_requests_failure_is_best_effort(self):
        client = FakeClient(
            requests=[],
            machines=[{"machine_id": "i-1", "status": "pending"}],
            fail_list=True,
        )
        with _patch_orb(client):
            out = asyncio.run(orb_lambda._dispatch({"action": "status"}))

        # list_requests failed -> no get_request_status, but still list_machines + return state.
        self.assertEqual(client.calls, [("list_requests",), ("list_machines",)])
        self.assertEqual(out["result"]["count"], 1)

    def test_one_request_status_failure_continues_others(self):
        client = FakeClient(
            requests=[{"request_id": "req-1"}, {"request_id": "req-2"}],
            machines=[{"machine_id": "i-1", "status": "running"}],
            fail_status_for=("req-1",),
        )
        with _patch_orb(client):
            out = asyncio.run(orb_lambda._dispatch({"action": "status"}))

        # req-1 raised but req-2 still synced, then list_machines still ran.
        self.assertEqual(
            client.calls,
            [
                ("list_requests",),
                ("get_request_status", ("req-1",)),
                ("get_request_status", ("req-2",)),
                ("list_machines",),
            ],
        )
        self.assertEqual(out["result"]["count"], 1)

    def test_request_scoped_status_skips_reconcile(self):
        client = FakeClient(requests=[{"request_id": "req-1"}], machines=[])
        with _patch_orb(client):
            out = asyncio.run(
                orb_lambda._dispatch({"action": "status", "request_id": "req-9"})
            )

        # request_id branch: only get_request_status(["req-9"]); no list_requests/list_machines.
        self.assertEqual(client.calls, [("get_request_status", ("req-9",))])
        self.assertEqual(out["action"], "status")

    def test_handler_wraps_status_in_200_envelope(self):
        client = FakeClient(
            requests=[{"request_id": "req-1"}],
            machines=[{"machine_id": "i-1", "status": "running"}],
        )
        with _patch_orb(client):
            resp = orb_lambda.handler({"action": "status"}, None)

        self.assertEqual(resp["statusCode"], 200)
        self.assertEqual(resp["body"]["result"]["count"], 1)

    def test_aws_wire_logs_toggle_off_by_default(self):
        import logging

        for name in ("boto3", "botocore", "urllib3"):
            logging.getLogger(name).setLevel(logging.WARNING)
        client = FakeClient(requests=[], machines=[])
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop("ORB_DEBUG_AWS", None)
            with _patch_orb(client):
                asyncio.run(orb_lambda._dispatch({"action": "status"}))
        # Default: AWS SDK loggers left as-is (not raised to DEBUG).
        self.assertEqual(logging.getLogger("botocore").level, logging.WARNING)

    def test_aws_wire_logs_toggle_on_raises_botocore(self):
        import logging

        for name in ("boto3", "botocore", "urllib3"):
            logging.getLogger(name).setLevel(logging.WARNING)
        client = FakeClient(requests=[], machines=[])
        with mock.patch.dict(os.environ, {"ORB_DEBUG_AWS": "1"}):
            with _patch_orb(client):
                asyncio.run(orb_lambda._dispatch({"action": "status"}))
        # Toggle on: botocore/boto3/urllib3 raised to DEBUG so wire logs reach CloudWatch.
        for name in ("boto3", "botocore", "urllib3"):
            self.assertEqual(logging.getLogger(name).level, logging.DEBUG)
        # Reset so we don't leak DEBUG into other tests' loggers.
        for name in ("boto3", "botocore", "urllib3"):
            logging.getLogger(name).setLevel(logging.WARNING)

    def test_requests_without_id_are_skipped(self):
        client = FakeClient(
            requests=[{"request_id": "req-1"}, {"status": "orphan"}, {"request_id": ""}],
            machines=[],
        )
        with _patch_orb(client):
            asyncio.run(orb_lambda._dispatch({"action": "status"}))

        # Only the one well-formed request id is synced.
        self.assertEqual(
            client.calls,
            [("list_requests",), ("get_request_status", ("req-1",)), ("list_machines",)],
        )

    def test_terminal_requests_are_skipped(self):
        # Terminal requests (failed/complete/cancelled) must not be synced: their state can't
        # change, and syncing makes ORB log a transition ERROR. Only the in-progress one syncs.
        client = FakeClient(
            requests=[
                {"request_id": "req-1", "status": "failed"},
                {"request_id": "req-2", "status": "complete"},
                {"request_id": "req-3", "status": "cancelled"},
                {"request_id": "req-4", "status": "pending"},
            ],
            machines=[{"machine_id": "i-1", "status": "running"}],
        )
        with _patch_orb(client):
            out = asyncio.run(orb_lambda._dispatch({"action": "status"}))

        self.assertEqual(
            client.calls,
            [
                ("list_requests",),
                ("get_request_status", ("req-4",)),
                ("list_machines",),
            ],
        )
        self.assertEqual(out["result"]["count"], 1)

    def test_missing_status_falls_back_to_syncing(self):
        # No status field at all -> behave exactly as before (sync it). Guards against a wrong
        # guess at the orb-py field name turning into a regression.
        client = FakeClient(requests=[{"request_id": "req-1"}], machines=[])
        with _patch_orb(client):
            asyncio.run(orb_lambda._dispatch({"action": "status"}))

        self.assertEqual(
            client.calls,
            [("list_requests",), ("get_request_status", ("req-1",)), ("list_machines",)],
        )

    def test_unknown_status_value_falls_back_to_syncing(self):
        # An in-progress / unrecognized status (not in TERMINAL_REQUEST_STATES) is still synced.
        client = FakeClient(
            requests=[{"request_id": "req-1", "status": "provisioning"}], machines=[]
        )
        with _patch_orb(client):
            asyncio.run(orb_lambda._dispatch({"action": "status"}))

        self.assertEqual(
            client.calls,
            [("list_requests",), ("get_request_status", ("req-1",)), ("list_machines",)],
        )

    def test_terminal_status_via_state_field(self):
        # The field may be named 'state' instead of 'status'; terminal values there are skipped too.
        client = FakeClient(
            requests=[
                {"request_id": "req-1", "state": "FAILED"},  # case-insensitive
                {"request_id": "req-2", "state": "pending"},
            ],
            machines=[],
        )
        with _patch_orb(client):
            asyncio.run(orb_lambda._dispatch({"action": "status"}))

        self.assertEqual(
            client.calls,
            [("list_requests",), ("get_request_status", ("req-2",)), ("list_machines",)],
        )


class AssertGridConfigTests(unittest.TestCase):
    """_assert_grid_config: templates are baked at deploy time, so cold start only asserts the
    DynamoDB table prefix is set (orb-py would otherwise silently use its 'hostfactory' default).
    """

    def test_missing_table_prefix_raises(self):
        # ORB_CONFIG_DIR set but no table prefix -> fail loud.
        env = {"ORB_CONFIG_DIR": "/var/task/orb-config"}
        with mock.patch.dict(os.environ, env, clear=False):
            os.environ.pop("ORB_AWS_STORAGE__DYNAMODB__TABLE_PREFIX", None)
            with self.assertRaises(RuntimeError):
                orb_lambda._assert_grid_config()

    def test_table_prefix_present_passes(self):
        env = {
            "ORB_CONFIG_DIR": "/var/task/orb-config",
            "ORB_AWS_STORAGE__DYNAMODB__TABLE_PREFIX": "orb-test",
        }
        with mock.patch.dict(os.environ, env, clear=False):
            orb_lambda._assert_grid_config()  # no raise

    def test_no_config_dir_is_noop(self):
        # Local/test use without a bundled config dir: skip the assertion entirely.
        env = dict(os.environ)
        env.pop("ORB_CONFIG_DIR", None)
        env.pop("ORB_AWS_STORAGE__DYNAMODB__TABLE_PREFIX", None)
        with mock.patch.dict(os.environ, env, clear=True):
            orb_lambda._assert_grid_config()  # no raise


class ShippedConfigJsonTests(unittest.TestCase):
    """Guard the invariants of the bundled config/config.json that env-driving relies on.

    These assert against the REAL shipped file (not a fixture), so a future edit that
    reintroduces a stale value fails here instead of at Lambda cold start.
    """

    import json as _json

    def _load(self):
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "config", "config.json")
        with open(path) as f:
            return self._json.load(f)

    def test_dynamodb_profile_is_falsy(self):
        # orb-py's DynamodbStrategyConfig.profile defaults to "default" (a NAMED profile). In
        # Lambda there are no named profiles, so a truthy value makes boto3 raise ProfileNotFound
        # (session_factory.create_session takes the profile_name branch). Shipping "" keeps it
        # falsy => ORB uses the execution-role credential chain. Must not regress.
        cfg = self._load()
        for prov in cfg["provider"]["providers"]:
            ddb = prov["config"]["storage"]["dynamodb"]
            self.assertFalse(
                ddb.get("profile", "default"),
                "config.json provider dynamodb.profile must be falsy (\"\") so boto3 uses the "
                "credential chain, not a named profile that does not exist in Lambda.",
            )

    def test_region_and_table_prefix_not_pinned_in_file(self):
        # region + table_prefix come from the ORB_AWS_* env layer. A value in the file would be
        # an init kwarg that, by pydantic-settings precedence, beats the env var — so they must
        # stay absent here.
        cfg = self._load()
        for prov in cfg["provider"]["providers"]:
            ddb = prov["config"]["storage"]["dynamodb"]
            self.assertNotIn("table_prefix", ddb)
            self.assertNotIn("region", ddb)
        # And the deprecated root storage.dynamodb_strategy block must not be reintroduced.
        self.assertNotIn("dynamodb_strategy", cfg["storage"])


if __name__ == "__main__":
    unittest.main()
