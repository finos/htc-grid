"""
Threaded Grid Connector DAG Adapter.

Implements a long-lived worker-thread model with:
- an incoming tasks queue (enqueue-only from submit_tasks)
- a completed results queue (drain-only from poll_completed)

See docs/THREADED_CONNECTOR_ADAPTER_SPEC.md for the intended behavior.
"""

from __future__ import annotations

import json
import logging
import threading
import time
from collections import deque
from dataclasses import dataclass
from typing import Any, Deque, Dict, Hashable, List, Optional, Set

from utils.dag.grid_connector_factory import BaseGridConnectorFactory, GridConnectorFactory
from utils.dag.base.base_dag import BaseDAG


@dataclass(frozen=True)
class QueuedTask:
    node_id: Hashable
    task_definition: Dict[str, Any]


@dataclass
class SessionState:
    session_id: str

    # full response from the connector
    submission_handle: Any

    # Mapping from grid task IDs (what the connector returns in results["finished"]) back to
    # DAG node IDs (what the scheduler understands).
    grid_to_dag: Dict[str, Hashable]

    # The same grid task ID can appear on every get_results() call.
    # remaining_grid_task_ids lets the worker ignore already-processed IDs
    # and avoid pushing the same node_id into _results
    remaining_grid_task_ids: Set[str]


@dataclass(frozen=True)
class WorkerError:
    thread_id: int
    stage: str
    error: Exception
    when_ts: float


class GridConnectorDagAdapter:
    """Threaded connector adapter skeleton based on THREADED_CONNECTOR_ADAPTER_SPEC.md."""

    def __init__(
        self,
        config: Dict[str, Any],
        logger: logging.Logger,
        grid_connector: Any = None,
        connector_factory: Optional[BaseGridConnectorFactory] = None,
    ) -> None:
        self._logger = logger
        self.config = config
        self.grid_connector = grid_connector
        self._connector_factory: BaseGridConnectorFactory = connector_factory or GridConnectorFactory(
            config=self.config,
            prototype_connector=self.grid_connector,
        )

        self.retry_attempts = int(config.get("retry_attempts", 3))

        self.num_worker_threads = int(config.get("num_worker_threads", config.get("num_connector_threads", 2)))
        if self.num_worker_threads <= 0:
            raise ValueError(f"num_worker_threads must be > 0 (got {self.num_worker_threads})")
        self.max_dequeue_per_loop = int(config.get("max_dequeue_per_loop", 100))
        if self.max_dequeue_per_loop <= 0:
            raise ValueError(f"max_dequeue_per_loop must be > 0 (got {self.max_dequeue_per_loop})")
        self.poll_timeout_sec = float(config.get("poll_timeout_sec", 0.01))
        self.poll_interval_sec = float(config.get("poll_interval_sec", 0.05))

        self._stop_event = threading.Event()

        self._tasks: Deque[QueuedTask] = deque()
        self._results: Deque[Hashable] = deque()

        self._tasks_condition = threading.Condition()
        self._results_condition = threading.Condition()

        self._queued_or_inflight: Set[Hashable] = set()

        self._active_sessions_count = 0
        self._active_sessions_lock = threading.Lock()

        self._errors: Deque[WorkerError] = deque()
        self._errors_lock = threading.Lock()
        self._fatal_error: Optional[WorkerError] = None

        self._threads: List[threading.Thread] = []
        self._start_workers()

        self._logger.info(
            "Threaded adapter initialized "
            f"(workers={self.num_worker_threads}, max_dequeue_per_loop={self.max_dequeue_per_loop})"
        )

    def _start_workers(self) -> None:
        for thread_id in range(self.num_worker_threads):
            t = threading.Thread(
                target=self._worker_main_loop,
                args=(thread_id,),
                name=f"GridConnectorDagAdapter-W{thread_id}",
                daemon=True,
            )
            t.start()
            self._threads.append(t)

    def shutdown(self, wait: bool = True, timeout: Optional[float] = None) -> None:
        self._stop_event.set()
        with self._tasks_condition:
            self._tasks_condition.notify_all()
        with self._results_condition:
            self._results_condition.notify_all()

        if not wait:
            return

        deadline = None if timeout is None else (time.time() + timeout)
        for t in self._threads:
            join_timeout = None if deadline is None else max(0.0, deadline - time.time())
            t.join(timeout=join_timeout)

    def __del__(self) -> None:
        try:
            self.shutdown(wait=False)
        except Exception:
            pass

    def submit_tasks(self, node_ids: List[str], dag_container: BaseDAG) -> Dict[Any, Dict[str, str]]:
        """
        Enqueue tasks for worker threads.

        - Marks tasks as submitted on the scheduler thread to avoid re-queueing.
        - Builds task definitions on the scheduler thread to avoid multi-threaded DAG access.
        """
        self.raise_if_failed()
        if not node_ids:
            return {}

        items: List[QueuedTask] = []

        for node_id in node_ids:
            task_definition = dag_container.build_grid_task(node_id)
            items.append(QueuedTask(node_id=node_id, task_definition=task_definition))

        enqueued_ids: List[Hashable] = []
        with self._tasks_condition:
            for item in items:
                if item.node_id in self._queued_or_inflight:
                    continue
                self._queued_or_inflight.add(item.node_id)
                self._tasks.append(item)
                enqueued_ids.append(item.node_id)

            # notify threads that new tasks are ready to be submitted to the grid
            if enqueued_ids:
                self._tasks_condition.notify_all()

        if enqueued_ids and hasattr(dag_container, "mark_task_submitted"):
            for node_id in enqueued_ids:
                dag_container.mark_task_submitted(node_id)  # type: ignore[attr-defined]

        if enqueued_ids:
            self._logger.info(
                f"Enqueued {len(enqueued_ids)}/{len(node_ids)} tasks"
            )
        return {}

    def poll_completed(self) -> List[Hashable]:
        """Drain completed DAG task IDs from the results queue."""
        self.raise_if_failed()
        completed: List[Hashable] = []
        with self._results_condition:
            while self._results:
                completed.append(self._results.popleft())
            if completed:
                self._results_condition.notify_all()
        if completed:
            with self._tasks_condition:
                for node_id in completed:
                    self._queued_or_inflight.discard(node_id)
        return completed

    def active_count(self) -> int:
        """Return number of active submissions across all workers."""
        with self._active_sessions_lock:
            return self._active_sessions_count

    def get_errors(self) -> List[WorkerError]:
        """Return a snapshot of worker errors (if any)."""
        with self._errors_lock:
            return list(self._errors)

    def raise_if_failed(self) -> None:
        """Raise if a worker hit a fatal error or all workers stopped."""
        if self._fatal_error is not None:
            err = self._fatal_error
            raise RuntimeError(f"Threaded adapter worker failed (thread={err.thread_id}, stage={err.stage}): {err.error}")

        if self._threads and not any(t.is_alive() for t in self._threads):
            raise RuntimeError("Threaded adapter has no live worker threads")

    def _record_error(self, thread_id: int, stage: str, exc: Exception) -> None:
        with self._errors_lock:
            err = WorkerError(thread_id=thread_id, stage=stage, error=exc, when_ts=time.time())
            self._errors.append(err)
            if stage in {"worker_crash"} and self._fatal_error is None:
                self._fatal_error = err

    @staticmethod
    def _extract_task_ids(submission_resp: Any) -> List[str]:
        if submission_resp is None:
            return []
        if isinstance(submission_resp, str):
            try:
                parsed = json.loads(submission_resp)
                if isinstance(parsed, dict) and "task_ids" in parsed:
                    return parsed.get("task_ids") or []
            except Exception:
                return []
        if isinstance(submission_resp, dict):
            return submission_resp.get("task_ids") or []
        task_ids = getattr(submission_resp, "task_ids", None)
        if task_ids:
            return list(task_ids)
        if hasattr(submission_resp, "get"):
            try:
                return submission_resp.get("task_ids", [])  # type: ignore[no-any-return]
            except Exception:
                return []
        return []

    @staticmethod
    def _extract_session_id(submission_resp: Any) -> Optional[str]:
        if submission_resp is None:
            return None
        if isinstance(submission_resp, str):
            try:
                parsed = json.loads(submission_resp)
                if isinstance(parsed, dict) and "session_id" in parsed:
                    return parsed.get("session_id")
            except Exception:
                return submission_resp
        if isinstance(submission_resp, dict):
            return submission_resp.get("session_id")
        sess = getattr(submission_resp, "session_id", None)
        if sess:
            return str(sess)
        if hasattr(submission_resp, "get"):
            try:
                return submission_resp.get("session_id", None)  # type: ignore[no-any-return]
            except Exception:
                return None
        return None

    @staticmethod
    def _extract_finished_task_ids(grid_response: Any) -> List[str]:
        if not grid_response:
            return []
        if isinstance(grid_response, dict):
            finished = grid_response.get("finished") or []
            return [str(x) for x in finished]
        if hasattr(grid_response, "finished"):
            return [str(x) for x in getattr(grid_response, "finished", [])]
        if hasattr(grid_response, "get"):
            try:
                finished = grid_response.get("finished") or []  # type: ignore[assignment]
                return [str(x) for x in finished]
            except Exception:
                return []
        return []

    def _worker_main_loop(self, thread_id: int) -> None:
        """
        Worker thread main loop.

        Responsibilities:
        <1.> Creates a thread-local grid connector
        <2.> Repeatedly dequeue up to `max_dequeue_per_loop` queued tasks and submit them as one grid session.
        <3.> Track the submitted session locally (`active_sessions`) and poll it for finished tasks.
        <4.> For each finished grid task ID, map it back to the DAG `node_id` and push it into the shared results queue.

        Concurrency model:
        - Uses `self._tasks_condition` to wait for new tasks and to dequeue atomically.
        - Uses `self._results_condition` to push completed node IDs for `poll_completed()` to drain.
        - Stops when `self._stop_event` is set; `shutdown()` wakes sleepers via `notify_all()`.

        Error handling:
        - if submissions fail after all retries, tasks return back into the queue.

        """
        logger = logging.getLogger(f"GridConnectorDagAdapter-W{thread_id}")

        # <1.> Creates a thread-local grid connector
        try:
            connector = self._connector_factory.create(thread_id=thread_id, logger=logger)
            logger.info(f"Thread {thread_id}: initialized")
        except Exception as e:
            self._record_error(thread_id, "init_connector", e)
            logger.error(f"Thread {thread_id}: failed to initialize connector: {e}", exc_info=True)
            return

        active_sessions: Dict[str, SessionState] = {}
        local_session_counter = 0

        try:
            while not self._stop_event.is_set():
                new_items: List[QueuedTask] = []

                # <2.A> Repeatedly dequeue up to `max_dequeue_per_loop`
                with self._tasks_condition:
                    if not self._tasks and not active_sessions and not self._stop_event.is_set():
                        self._tasks_condition.wait(timeout=self.poll_interval_sec)

                    while self._tasks and len(new_items) < self.max_dequeue_per_loop:
                        new_items.append(self._tasks.popleft())

                # <2.B> Submit new items
                if new_items:
                    batch = new_items
                    task_definitions = [t.task_definition for t in batch]
                    node_ids = [t.node_id for t in batch]

                    submission_handle = None
                    # Stores the last exception that occurred when trying to submit tasks, so it can be logged if all retry attempts fail
                    last_exc: Optional[Exception] = None

                    for attempt in range(self.retry_attempts):
                        try:
                            submission_handle = connector.send(task_definitions)
                            logger.info(f"Thread {thread_id}: submited {len(task_definitions)}")
                            break
                        except Exception as e:
                            last_exc = e
                            self._record_error(thread_id, "send", e)
                            if attempt < self.retry_attempts - 1:
                                time.sleep(1.0)

                    if submission_handle is None:
                        if last_exc:
                            logger.error(f"Thread {thread_id}: failed to submit batch: {last_exc}", exc_info=True)
                        with self._tasks_condition:
                            for t in batch:
                                self._tasks.appendleft(t)
                            self._tasks_condition.notify_all()
                        continue

                    session_id = self._extract_session_id(submission_handle)
                    task_ids = self._extract_task_ids(submission_handle)

                    if not session_id:
                        local_session_counter += 1
                        session_id = f"t{thread_id}-{int(time.time())}-{local_session_counter}"

                    if not task_ids or len(task_ids) != len(node_ids):
                        self._record_error(
                            thread_id,
                            "invalid_submission_response",
                            ValueError(f"Expected {len(node_ids)} task_ids, got {len(task_ids)}"),
                        )
                        with self._tasks_condition:
                            for t in batch:
                                self._tasks.appendleft(t)
                            self._tasks_condition.notify_all()
                        continue

                    grid_to_dag: Dict[str, Hashable] = {}
                    for node_id, grid_tid in zip(node_ids, task_ids):
                        grid_to_dag[str(grid_tid)] = node_id

                    remaining = set(grid_to_dag.keys())
                    active_sessions[session_id] = SessionState(
                        session_id=session_id,
                        submission_handle=submission_handle,
                        grid_to_dag=grid_to_dag,
                        remaining_grid_task_ids=remaining,
                    )

                    with self._active_sessions_lock:
                        self._active_sessions_count += 1

                # iterate over all in‑flight grid submissions owned by the worker thread
                # if a session has new completed tasks, add them to the completed list
                # if all tasks of a session completed, remove session from the active_sessions.
                for session_id, session_obj in list(active_sessions.items()):
                    try:
                        results = connector.get_results(session_obj.submission_handle, timeout_sec=self.poll_timeout_sec)
                    except Exception as e:
                        self._record_error(thread_id, "get_results", e)
                        continue

                    finished_grid_task_ids = self._extract_finished_task_ids(results)
                    if not finished_grid_task_ids:
                        continue

                    for grid_task_id in finished_grid_task_ids:
                        # This task has been returned in previous call and sent to the completed queue.
                        if grid_task_id not in session_obj.remaining_grid_task_ids:
                            continue

                        node_id = session_obj.grid_to_dag.get(grid_task_id)
                        if node_id is None:
                            self._record_error(thread_id, "map_grid_to_dag", KeyError(grid_task_id))
                            continue

                        session_obj.remaining_grid_task_ids.remove(grid_task_id)

                        with self._results_condition:
                            if self._stop_event.is_set():
                                return
                            self._results.append(node_id)
                            self._results_condition.notify_all()

                    if not session_obj.remaining_grid_task_ids:
                        del active_sessions[session_id]
                        with self._active_sessions_lock:
                            self._active_sessions_count = max(0, self._active_sessions_count - 1)

                if not new_items and active_sessions and self.poll_interval_sec:
                    time.sleep(self.poll_interval_sec)
        except Exception as e:
            self._record_error(thread_id, "worker_crash", e)
            logger.error(f"Thread {thread_id}: worker crashed: {e}", exc_info=True)
            return
