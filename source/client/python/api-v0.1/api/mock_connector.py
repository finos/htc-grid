# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import time
import uuid
import logging
from typing import Dict, List, Any, Optional
from api.connector_interface import GridConnectorInterface

logger = logging.getLogger("MockGridConnector")

class MockGridConnector(GridConnectorInterface):
    """Mock implementation of the Grid Connector for local testing"""

    def __init__(self):
        """Initialize the mock grid connector"""
        self.active_submissions = {}  # Mapping of submission ID to task status
        self.config = None
        logger.info("Mock Grid Connector initialized")

    def init(self, config: Dict[str, Any]) -> None:
        """Initialize the grid connector

        Args:
            config: Configuration dictionary
        """
        self.config = config
        logger.info("Mock Grid Connector configuration loaded")

    def authenticate(self) -> None:
        """Authenticate with the grid"""
        # Mock implementation - always succeeds
        logger.info("Mock authentication successful")

    def send(self, task_vector: List[Dict[str, Any]]) -> object:
        """Submit a vector of tasks to the grid

        Args:
            task_vector: List of task definitions

        Returns:
            Mock PostSubmitResponse object for tracking
        """
        # Generate a unique submission ID
        session_id = str(uuid.uuid4())

        # Generate task IDs in HTC Grid format
        task_ids = [f"{session_id}_{i}" for i in range(len(task_vector))]

        submitted_at = time.monotonic()
        durations_sec: List[float] = []
        for task in task_vector:
            try:
                worker_args = task.get("worker_arguments", [])
                sleep_ms = int(worker_args[0]) if worker_args else 0
                durations_sec.append(max(0.0, sleep_ms / 1000.0))
            except Exception:
                durations_sec.append(0.0)

        # Model a grid-style submission: tasks run "in parallel", and the session completes
        # when the longest-running task completes.
        task_complete_at = [submitted_at + d for d in durations_sec]
        session_complete_at = max(task_complete_at) if task_complete_at else submitted_at

        # Store submission info
        self.active_submissions[session_id] = {
            "status": "processing",
            "tasks": task_vector,
            "task_ids": task_ids,
            "results": None,
            "thread": None,
            "submitted_at": submitted_at,
            "task_complete_at": task_complete_at,
            "session_complete_at": session_complete_at,
        }

        # Create mock PostSubmitResponse object
        class MockPostSubmitResponse:
            def __init__(self, session_id, task_ids):
                self.session_id = session_id
                self.task_ids = task_ids

            def get(self, key, default=None):
                """Make it dict-like for compatibility"""
                if key == 'session_id':
                    return self.session_id
                elif key == 'task_ids':
                    return self.task_ids
                return default

            def __getitem__(self, key):
                """Support dict-like access"""
                if key == 'session_id':
                    return self.session_id
                elif key == 'task_ids':
                    return self.task_ids
                raise KeyError(key)

            def __contains__(self, key):
                """Support 'in' operator"""
                return key in ['session_id', 'task_ids']

            def __str__(self):
                return f"{{'session_id': '{self.session_id}', 'task_ids': {self.task_ids}}}"

        response = MockPostSubmitResponse(session_id, task_ids)
        logger.debug(f"Mock submission created: {session_id} with {len(task_vector)} tasks")
        return response

    def get_results(self, submission_dict: Dict[str, Any], timeout_sec: Optional[int] = None) -> Optional[object]:
        """Get results for a specific submission

        Args:
            submission_dict: Dictionary with session_id and task_ids
            timeout_sec: Maximum wait time in seconds (0 for non-blocking check)

        Returns:
            Mock GetResponse object if complete, None if still in progress
        """
        session_id = submission_dict.get('session_id')
        if not session_id or session_id not in self.active_submissions:
            logger.warning(f"Unknown session ID: {session_id}")
            return None

        submission = self.active_submissions[session_id]
        now = time.monotonic()

        all_task_ids: List[str] = list(submission.get("task_ids") or [])

        finished_task_ids: List[str] = []
        if submission.get("status") == "complete":
            finished_task_ids = all_task_ids
        else:
            task_complete_at = submission.get("task_complete_at")
            if isinstance(task_complete_at, list) and len(task_complete_at) == len(all_task_ids):
                finished_task_ids = [
                    task_id
                    for task_id, complete_at in zip(all_task_ids, task_complete_at)
                    if now >= float(complete_at)
                ]

            if len(finished_task_ids) == len(all_task_ids) and all_task_ids:
                submission["status"] = "complete"

        # Always return cumulative "finished so far" in exact HTC Grid format.
        return {
            "cancelled": [],
            "cancelled_OUTPUT": [],
            "failed": [],
            "failed_OUTPUT": [],
            "finished": finished_task_ids,
            "finished_OUTPUT": ["mock_output"] * len(finished_task_ids),
            "metadata": {"tasks_in_response": len(finished_task_ids)},
        }

    def _process_tasks(self, submission_id: str, task_vector: List[Dict[str, Any]], task_ids: List[str]) -> None:
        """Process tasks in the background

        Args:
            submission_id: Submission ID
            task_vector: List of task definitions
            task_ids: List of task IDs
        """
        results = {}

        for i, task in enumerate(task_vector):
            # Extract sleep duration from first parameter
            try:
                sleep_ms = int(task["worker_arguments"][0])

                # Mark task as completed
                results[f"task_{i}"] = {
                    "status": "completed",
                    "result": f"Mock result for task {i}",
                    "worker_arguments": task["worker_arguments"]
                }

            except (KeyError, IndexError, ValueError) as e:
                logger.error(f"Error processing mock task {i}: {str(e)}")
                results[f"task_{i}"] = {
                    "status": "failed",
                    "error": str(e)
                }

        # Update submission status
        self.active_submissions[submission_id]["status"] = "complete"
        self.active_submissions[submission_id]["results"] = results
        self.active_submissions[submission_id]["session_complete_at"] = time.monotonic()

        logger.info(f"Mock submission {submission_id} processing completed")
