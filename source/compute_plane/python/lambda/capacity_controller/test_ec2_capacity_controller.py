# Copyright 2024 Amazon.com, Inc. or its affiliates.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

"""Unit tests for the EC2 capacity controller backlog read + desired-count math.

Runnable with plain stdlib (no pytest): `python3 -m unittest test_ec2_capacity_controller`.
The controller imports boto3 / aws_lambda_powertools and the api/drain/orb_client modules at
load and constructs the queue + state-table singletons at import; none of those AWS deps are
installed in dev, so we stub them in sys.modules (and via env vars) before importing.
"""

from __future__ import annotations

import os
import sys
import types
import unittest
from unittest import mock


FAKE_BACKLOG = {"n": 0}


def _install_stub_modules() -> None:
    """Stub the deps the controller imports/instantiates at module load."""
    if "boto3" not in sys.modules:
        sys.modules["boto3"] = mock.MagicMock(name="boto3")

    if "aws_lambda_powertools" not in sys.modules:
        powertools = types.ModuleType("aws_lambda_powertools")

        class _Logger:
            def __init__(self, *a, **k):
                pass

            def __getattr__(self, _name):  # info/debug/warning/exception -> no-ops
                return lambda *a, **k: None

            def inject_lambda_context(self, *a, **k):
                def _decorator(func):
                    return func

                return _decorator

        powertools.Logger = _Logger
        sys.modules["aws_lambda_powertools"] = powertools

    # api.queue_manager.queue_manager -> a fake queue whose length tracks FAKE_BACKLOG.
    if "api" not in sys.modules:
        sys.modules["api"] = types.ModuleType("api")

    qm_mod = types.ModuleType("api.queue_manager")

    class _FakeQueue:
        def get_queue_length(self):
            return FAKE_BACKLOG["n"]

    qm_mod.queue_manager = lambda *a, **k: _FakeQueue()
    sys.modules["api.queue_manager"] = qm_mod

    stm_mod = types.ModuleType("api.state_table_manager")
    stm_mod.state_table_manager = lambda *a, **k: mock.MagicMock(name="state_table")
    sys.modules["api.state_table_manager"] = stm_mod

    # drain / orb_client are imported but only called inside the handler; stub as MagicMocks.
    drain_mod = types.ModuleType("drain")
    drain_mod.LIFECYCLE_DRAINING = "draining"
    drain_mod.read_drain_state = lambda ids: {}
    drain_mod.busy_instance_ids = lambda st: set()
    drain_mod.cordon = mock.MagicMock(name="cordon")
    drain_mod.uncordon = mock.MagicMock(name="uncordon")
    drain_mod.resend_stop = mock.MagicMock(name="resend_stop")
    sys.modules["drain"] = drain_mod

    orb_mod = types.ModuleType("orb_client")
    orb_mod.list_live = lambda: []
    orb_mod.create = mock.MagicMock(name="create", return_value={})
    orb_mod.terminate = mock.MagicMock(name="terminate", return_value={})
    sys.modules["orb_client"] = orb_mod


os.environ.update(
    {
        "REGION": "eu-west-1",
        "TASK_QUEUE_SERVICE": "SQS",
        "TASK_QUEUE_CONFIG": "{}",
        "TASKS_QUEUE_NAME": "htc_task_queue_aws__0",
        "STATE_TABLE_NAME": "tasks_state_table",
        "PAIR_CPU": "1",
        "MIN_VCPUS": "0",
        "MAX_VCPUS": "64",
        "TARGET_PENDING_PER_PAIR": "4",
    }
)
_install_stub_modules()

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ec2_capacity_controller as cc  # noqa: E402


def _machine(mid, vcpus=None, top_vcpus=None, provider_vcpus=None, memory_mib=None):
    """Build a fake ORB status machine dict. vcpus sets the top-level field for convenience."""
    m = {"machine_id": mid, "status": "running"}
    if vcpus is not None:
        m["vcpus"] = vcpus
    if top_vcpus is not None:
        m["vcpus"] = top_vcpus
    if provider_vcpus is not None:
        m["provider_data"] = {"vcpus": provider_vcpus}
    if memory_mib is not None:
        m["memory_mib"] = memory_mib
    return m


class ReadBacklogTest(unittest.TestCase):
    def test_reads_queue_length_as_float(self):
        FAKE_BACKLOG["n"] = 7
        self.assertEqual(cc._read_backlog(), 7.0)
        self.assertIsInstance(cc._read_backlog(), float)

    def test_empty_queue(self):
        FAKE_BACKLOG["n"] = 0
        self.assertEqual(cc._read_backlog(), 0.0)


class VcpusOfTest(unittest.TestCase):
    """_vcpus_of reads vcpus from ORB status (top-level or provider_data), with memory and
    1-worker-per-instance fallbacks when capacity data is absent."""

    def test_top_level_vcpus(self):
        self.assertEqual(cc._vcpus_of(_machine("i-1", top_vcpus=4)), 4)

    def test_provider_data_fallback(self):
        self.assertEqual(cc._vcpus_of(_machine("i-2", provider_vcpus=8)), 8)

    def test_no_data_defaults_to_one_worker_per_instance(self):
        # No vcpu AND no memory -> 1 worker == 1 instance, i.e. PAIR_CPU vCPUs (one pair).
        self.assertEqual(cc._vcpus_of({"machine_id": "i-3"}), cc.PAIR_CPU)

    def test_zero_vcpu_no_memory_defaults_to_one_worker(self):
        self.assertEqual(cc._vcpus_of(_machine("i-4", top_vcpus=0)), cc.PAIR_CPU)

    def test_memory_fallback_when_vcpus_missing(self):
        # No vcpus but memory known -> size by memory: floor(mem/PAIR_MEMORY) pairs * PAIR_CPU.
        # PAIR_MEMORY=2048, PAIR_CPU=1: 8192 MiB -> 4 pairs -> 4 vCPUs.
        self.assertEqual(cc._vcpus_of(_machine("i-5", memory_mib=8192)), 4 * cc.PAIR_CPU)

    def test_vcpus_preferred_over_memory(self):
        # When both present, real vcpus wins.
        self.assertEqual(cc._vcpus_of(_machine("i-6", top_vcpus=2, memory_mib=99999)), 2)

    def test_error_logged_when_no_capacity_data(self):
        with mock.patch.object(cc.logger, "error") as err:
            cc._vcpus_of({"machine_id": "i-7"})
            err.assert_called_once()

    def test_pairs_of_floors(self):
        # PAIR_CPU=1: pairs == vcpus
        self.assertEqual(cc._pairs_of(_machine("i-5", top_vcpus=4)), 4)


class DesiredVcpuTest(unittest.TestCase):
    """The handler's desired math: clamp(ceil(backlog / target_per_pair) * PAIR_CPU, MIN, MAX)."""

    def setUp(self):
        cc.orb_client.create.reset_mock()
        cc.orb_client.list_live = lambda: []  # no current capacity by default

    def _run(self, backlog):
        FAKE_BACKLOG["n"] = backlog
        return cc.handler({}, None)

    def test_zero_backlog_floors_to_min(self):
        res = self._run(0)
        self.assertEqual(res["desired_vcpus"], cc.MIN_VCPUS)

    def test_ceil_division_times_pair_cpu(self):
        # target_per_pair=4, PAIR_CPU=1: 5 pending -> ceil(5/4)=2 pairs -> 2 vCPUs
        res = self._run(5)
        self.assertEqual(res["desired_vcpus"], 2)

    def test_clamped_to_max(self):
        # 1000 pending -> ceil(1000/4)=250 vCPUs, clamped to MAX_VCPUS=64
        res = self._run(1000)
        self.assertEqual(res["desired_vcpus"], cc.MAX_VCPUS)


class CurrentVcpuTest(unittest.TestCase):
    """current_vcpus sums each active machine's vcpus (heterogeneous mix)."""

    def setUp(self):
        cc.orb_client.create.reset_mock()

    def test_sums_mixed_instance_types(self):
        cc.orb_client.list_live = lambda: [
            _machine("i-a", top_vcpus=4),  # m6i.xlarge-ish
            _machine("i-b", top_vcpus=2),  # m6i.large-ish
            _machine("i-c", provider_vcpus=2),  # vcpus only in provider_data
        ]
        FAKE_BACKLOG["n"] = 0
        res = cc.handler({}, None)
        self.assertEqual(res["current_vcpus"], 8)

    def test_deficit_requested_in_vcpus(self):
        # current 2 vCPUs, backlog 32 -> desired ceil(32/4)=8 pairs -> 8 vCPUs, deficit 6.
        cc.orb_client.list_live = lambda: [_machine("i-a", top_vcpus=2)]
        FAKE_BACKLOG["n"] = 32
        cc.handler({}, None)
        cc.orb_client.create.assert_called_once_with(6)


class ScaleDownTest(unittest.TestCase):
    """Surplus cordons whole instances by summed vCPUs (idle-first, then oldest)."""

    def setUp(self):
        cc.drain.cordon.reset_mock()
        cc.drain.busy_instance_ids = lambda st: set()  # nothing busy
        cc.drain.read_drain_state = lambda ids: {}

    def test_cordons_until_surplus_covered(self):
        # current 4+2+2=8 vCPUs, backlog 8 -> desired ceil(8/4)=2 pairs -> 2 vCPUs, surplus 6.
        # idle-first then oldest: cordon i-a(4) then i-b(2) = 6 >= 6, stop (i-c left running).
        cc.orb_client.list_live = lambda: [
            _machine("i-a", top_vcpus=4),
            _machine("i-b", top_vcpus=2),
            _machine("i-c", top_vcpus=2),
        ]
        FAKE_BACKLOG["n"] = 8
        cc.handler({}, None)
        cc.drain.cordon.assert_called_once()
        cordoned = cc.drain.cordon.call_args[0][0]
        self.assertEqual(set(cordoned), {"i-a", "i-b"})

    def test_throttling_skips_cordon(self):
        cc.drain.busy_instance_ids = lambda st: None  # state table throttling
        cc.orb_client.list_live = lambda: [_machine("i-a", top_vcpus=8)]
        FAKE_BACKLOG["n"] = 0
        cc.handler({}, None)
        cc.drain.cordon.assert_not_called()


if __name__ == "__main__":
    unittest.main()
