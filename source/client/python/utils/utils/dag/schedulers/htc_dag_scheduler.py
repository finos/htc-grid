"""
HTC DAG Scheduler: encapsulates the DAG processing loop previously in HTCClientDAG.run.
"""

import logging
import time
import traceback
from typing import Any, Dict

from utils.dag.base.base_dag import BaseDAG


class HTCDagScheduler:
    """Runs the DAG processing loop using provided collaborators."""

    def __init__(
        self,
        config: Dict[str, Any],
        dag_container: BaseDAG,
        grid_connector_adapter: Any,
        grid_connector: Any,
    ) -> None:
        self.dcon = dag_container
        self.grid_connector_adapter = grid_connector_adapter
        self.grid_connector = grid_connector
        self.config = config
        self.logger = logging.getLogger("HTCDagScheduler")

    def run(self) -> bool:
        """Execute the main DAG processing loop."""
        if not self.dcon.dag:
            self.logger.error("No DAG loaded for processing")
            return False

        self.logger.info("Starting DAG processing")
        start_time = time.time()

        try:
            iteration_count = 0
            previous_completed_count = 0  # Track completed tasks from previous iteration

            # <1.> While DAG is not complete...
            while not self.dcon.is_dag_complete():

                iteration_start = time.time()
                iteration_count += 1
                self.logger.info(f"Processing iteration {iteration_count}")

                # <2.> Find nodes that have no dependencies or all dependencies have been computed
                t21 = time.perf_counter()
                ready_nodes = self.dcon.get_ready_tasks()
                t22 = time.perf_counter()

                t31 = time.perf_counter()
                if ready_nodes:
                    self.logger.debug(f"# nodes/tasks about to be submitted for processing: {len(ready_nodes)}")
                    self.grid_connector_adapter.submit_tasks(ready_nodes, self.dcon)
                t32 = time.perf_counter()

                # <4.> Check if any of the previously submitted tasks have completed
                t41 = time.perf_counter()
                completed_dag_ids = list(self.grid_connector_adapter.poll_completed())
                t42 = time.perf_counter()

                # <5.> Update DAG mark newly completed tasks as completed!
                t51 = time.perf_counter()
                for dag_tid in completed_dag_ids:
                    self.dcon.mark_task_complete(dag_tid)
                t52 = time.perf_counter()
                # Calculate completed tasks this iteration
                completed_count = self.dcon.get_completed_task_count()
                completed_tasks_this_iteration = completed_count - previous_completed_count

                # Logging and Bookkeping #################################################################
                # Log timing breakdown for this iteration
                self._log_iteration_timings(
                    t21, t22, t31, t32, t41, t42, t51, t52,
                    ready_tasks_count=len(ready_nodes),
                    active_submissions_count=self.grid_connector_adapter.active_count(),
                    completed_tasks_this_iteration=completed_tasks_this_iteration
                )

                total_count = self.dcon.get_total_task_count()
                self.logger.info(f"Progress: {completed_count}/{total_count} tasks completed")

                # Optional DAG visualization
                if self.config.get("show_dag_visualization", False):
                    dag_viz = self.dcon.visualize_dag_status()
                    print(dag_viz)

                self._print_iteration_summary(
                    ready_tasks_count=len(ready_nodes),
                    active_submissions_count=self.grid_connector_adapter.active_count(),
                    completed_tasks_this_iteration=completed_tasks_this_iteration
                )

                # Update previous completed count for next iteration
                previous_completed_count = completed_count

                # Enforce minimum loop interval if configured
                min_interval = self.config.get("polling_interval_seconds", 0)
                elapsed = time.time() - iteration_start
                if min_interval and elapsed < min_interval:
                    sleep_duration = min_interval - elapsed
                    self.logger.debug(f"Sleeping {sleep_duration:.2f}s to respect polling interval")
                    time.sleep(sleep_duration)

            total_time = time.time() - start_time
            self.logger.info(f"DAG processing completed successfully in {total_time:.2f} seconds")
            self.logger.info(f"Total iterations: {iteration_count}")
            return True

        except Exception as e:
            self.logger.error(
                f"DAG processing failed: {str(e)}\n"
                f"Stack trace:\n{''.join(traceback.format_tb(e.__traceback__))}",
                exc_info=True,
            )

            return False

    def _print_iteration_summary(
        self,
        ready_tasks_count: int,
        active_submissions_count: int,
        completed_tasks_this_iteration: int
    ) -> None:
        """Print iteration status in a single line with brief abbreviations."""
        # Get DAG progress information
        completed_count = self.dcon.get_completed_task_count()
        total_count = self.dcon.get_total_task_count()
        progress_percentage = (completed_count / total_count * 100) if total_count > 0 else 0

        # Build status string with core metrics
        status_parts = [
            f"newRdy={ready_tasks_count}",
            f"A.S.={active_submissions_count}",
            f"doneNow={completed_tasks_this_iteration}",
            f"Prgs={completed_count}/{total_count}({progress_percentage:.1f}%)"
        ]

        # Add DAG status counts if available
        if self.dcon.dag:
            dag_summary = self.dcon.get_dag_summary()
            if dag_summary.get("status_counts"):
                status_counts = dag_summary["status_counts"]

                if "pending" in status_counts:
                    status_parts.append(f"Pend={status_counts['pending']}")
                if "submitted" in status_counts:
                    status_parts.append(f"Sub={status_counts['submitted']}")
                if "completed" in status_counts:
                    status_parts.append(f"Done={status_counts['completed']}")
                if "failed" in status_counts:
                    status_parts.append(f"Fail={status_counts['failed']}")

        self.logger.info(f"Status: {', '.join(status_parts)}")

    def _log_iteration_timings(
        self,
        t21: float,
        t22: float,
        t31: float,
        t32: float,
        t41: float,
        t42: float,
        t51: float,
        t52: float,
        ready_tasks_count: int,
        active_submissions_count: int,
        completed_tasks_this_iteration: int,
    ) -> None:
        """
        Log a one-line timing summary for key iteration segments with task counts.

        Example output:
            TIMINGS s:ready=0.0003 submit=0.0010 poll=0.0025 mark=0.0004 total=0.0042 newRdy=5 A.S.=26 doneNow=3
        """
        ready = t22 - t21
        submit = t32 - t31
        poll = t42 - t41
        mark = t52 - t51
        total = t52 - t21

        # Get total progress for logging
        completed_count = self.dcon.get_completed_task_count()
        total_count = self.dcon.get_total_task_count()

        self.logger.info(
            f"TIMINGS ready={ready:>7.4f}s submit={submit:>7.4f}s "
            f"poll={poll:>7.4f}s mark={mark:>7.4f}s total={total:>7.4f}s | "
            f"newRdy={ready_tasks_count:>6} ActSub={active_submissions_count:>6} doneNow={completed_tasks_this_iteration:>6} "
            f"totalDone={completed_count:>8}/{total_count:<8}"
        )
