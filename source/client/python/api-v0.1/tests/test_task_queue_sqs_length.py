# Copyright 2024 Amazon.com, Inc. or its affiliates.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

"""Regression test for QueueSQS.get_queue_length() attribute freshness.

boto3's SQS *resource* (`sqs_resource.get_queue_by_name(...)`) lazy-loads `.attributes` ONCE and
caches them for the life of the object. A long-lived caller -- e.g. the capacity_controller, which
builds its queue at module load and reuses it across every tick in a warm Lambda -- would otherwise
read the backlog captured at first access forever. If that first read happened while the queue was
empty, the controller sees backlog=0 permanently and never scales up, no matter how many tasks are
enqueued later. get_queue_length() must therefore reload() before reading.

Runnable with plain stdlib (no pytest/moto): `python3 -m unittest test_task_queue_sqs_length`.
"""

from __future__ import annotations

import os
import sys
import unittest
from unittest import mock

_HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.abspath(os.path.join(_HERE, "..")))                  # api-v0.1 (api.*)
sys.path.insert(0, os.path.abspath(os.path.join(_HERE, "..", "..", "utils")))   # utils.*
# grid_error_logger reads these at import; supply harmless values so the import doesn't KeyError.
os.environ.setdefault("ERROR_LOG_GROUP", "test")
os.environ.setdefault("ERROR_LOGGING_STREAM", "test")
os.environ.setdefault("REGION", "eu-west-1")


class _FakeSqsQueue:
    """Mimics a boto3 SQS Queue resource: .attributes is a frozen snapshot until reload()."""

    def __init__(self, live_values):
        # live_values: list of successive ApproximateNumberOfMessages the broker would report.
        self._live = list(live_values)
        # Initial lazy load captures the first value (as boto3 does on first .attributes access).
        self.attributes = {"ApproximateNumberOfMessages": str(self._live[0])}
        self.reload_calls = 0

    def reload(self):
        self.reload_calls += 1
        # Advance to the next broker-reported value, sticking on the last one.
        if len(self._live) > 1:
            self._live.pop(0)
        self.attributes = {"ApproximateNumberOfMessages": str(self._live[0])}


def _make_queue(fake):
    """Build a QueueSQS with boto3 stubbed so __init__ wires up our fake resource queue."""
    with mock.patch("boto3.resource") as m_res, mock.patch("boto3.client"):
        m_res.return_value.get_queue_by_name.return_value = fake
        from api.task_queue_sqs import QueueSQS

        return QueueSQS(endpoint_url=None, queue_name="q__0", region="eu-west-1")


class GetQueueLengthFreshnessTest(unittest.TestCase):
    def test_reloads_before_reading(self):
        # Captured 0 at init; broker now reports 1000. Must reflect 1000, not the stale 0.
        fake = _FakeSqsQueue([0, 1000])
        q = _make_queue(fake)
        self.assertEqual(q.get_queue_length(), 1000)
        self.assertGreaterEqual(fake.reload_calls, 1)

    def test_reflects_changing_backlog_across_calls(self):
        # Each call must see the current value, not the first one cached at construction.
        fake = _FakeSqsQueue([0, 500, 250, 0])
        q = _make_queue(fake)
        self.assertEqual(q.get_queue_length(), 500)
        self.assertEqual(q.get_queue_length(), 250)
        self.assertEqual(q.get_queue_length(), 0)

    def test_returns_int(self):
        fake = _FakeSqsQueue([42])
        q = _make_queue(fake)
        result = q.get_queue_length()
        self.assertEqual(result, 42)
        self.assertIsInstance(result, int)


if __name__ == "__main__":
    unittest.main()
