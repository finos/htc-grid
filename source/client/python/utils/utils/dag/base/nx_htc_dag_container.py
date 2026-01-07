# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

"""
DAG Manager: NetworkX-based DAG management and dependency tracking
"""

import logging
import threading
from typing import Any, Dict, Hashable, List, Optional, Set

import networkx as nx

from .base_dag import BaseDAG

logger = logging.getLogger("NxHtcDagContainer")


class NxHtcDagContainer(BaseDAG):
    """Manages DAG structure and task state using NetworkX"""

    def __init__(self, nx_dag: Optional[nx.DiGraph] = None):
        """Initialize DAG manager."""
        self.dag: Optional[nx.DiGraph] = None
        self._lock = threading.Lock()  # Thread safety for state updates
        logger.debug("DAG Manager initialized")

        if nx_dag:
            self.set_dag(nx_dag)

    def get_nodes_with_resolved_dependencies(self) -> List[Hashable]:
        """
        BaseDAG implementation: return nodes whose dependencies are satisfied.
        """
        return self.get_ready_tasks()

    def mark_node_completed(self, node_id: Hashable) -> bool:
        """
        BaseDAG implementation: mark a node as completed.
        """
        return self.mark_task_complete(node_id)

    def is_dag_completed(self) -> bool:
        """
        BaseDAG implementation: return True when all nodes are completed.
        """
        return self.is_dag_complete()

    def get_node_by_id(self, node_id: Hashable):
        """
        BaseDAG implementation: return the node object/data for the given node identifier.

        Args:
            node_id: The identifier of the node to retrieve

        Returns:
            The node data dictionary associated with the given ID, or None if not found
        """
        if not self.dag:
            return None

        if node_id not in self.dag.nodes():
            return None

        # with self._lock:
        return dict(self.dag.nodes[node_id])

    def build_grid_task(self, node_id: Hashable) -> Dict[str, Any]:
        """
        BaseDAG implementation: build a grid task definition for a DAG node.

        Currently this adapter maps DAG node metadata into the connector payload shape:
            {"worker_arguments": [...]}
        """
        node_data = self.get_node_by_id(node_id)
        if node_data is None:
            raise KeyError(f"Task {node_id} not found in DAG")
        return {"worker_arguments": node_data.get("worker_arguments", ["1000", "1", "1"])}

    ###########################################################################################################
    ###########################################################################################################
    ###########################################################################################################

    def set_dag(self, dag: nx.DiGraph) -> bool:
        """Set the DAG to be processed

        Args:
            dag: NetworkX DiGraph representing the task DAG

        Returns:
            True if DAG was set successfully, False otherwise
        """
        try:
            print("Setting DAG----")
            with self._lock:
                # Validate DAG structure
                if not self._validate_dag(dag):
                    logger.error("Invalid DAG structure")
                    return False

                self.dag = dag.copy()

                # Initialize task states if not already set
                for node_id in self.dag.nodes():
                    if 'status' not in self.dag.nodes[node_id]:
                        self.dag.nodes[node_id]['status'] = 'pending'

                logger.info(f"DAG set with {len(self.dag.nodes())} nodes and {len(self.dag.edges())} edges")
                return True

        except Exception as e:
            logger.error(f"Failed to set DAG: {str(e)}")
            return False

    def _validate_dag(self, dag: nx.DiGraph) -> bool:
        """Validate DAG structure

        Args:
            dag: DAG to validate

        Returns:
            True if DAG is valid, False otherwise
        """
        try:
            # Check if it's a DAG (no cycles)
            if not nx.is_directed_acyclic_graph(dag):
                logger.error("Graph contains cycles - not a valid DAG")
                return False

            # Check if all nodes have required attributes
            for node_id, node_data in dag.nodes(data=True):
                if 'task_type' not in node_data:
                    logger.error(f"Node {node_id} missing task_type attribute")
                    print(node_data)
                    return False

                if 'worker_arguments' not in node_data:
                    logger.error(f"Node {node_id} missing worker_arguments attribute")
                    return False

                # Validate worker_arguments format
                args = node_data['worker_arguments']
                if not isinstance(args, list) or len(args) != 3:
                    logger.error(f"Node {node_id} has invalid worker_arguments format")
                    return False

            return True

        except Exception as e:
            logger.error(f"DAG validation failed: {str(e)}")
            return False

    def get_ready_tasks(self) -> List[str]:
        """Get tasks that are ready for execution (all dependencies satisfied)

        Returns:
            List of task IDs ready for execution
        """
        if not self.dag:
            return []

        ready_tasks = []

        with self._lock:
            for node_id in self.dag.nodes():
                if self._is_task_ready(node_id):
                    ready_tasks.append(node_id)

        logger.debug(f"Found {len(ready_tasks)} ready tasks: {ready_tasks}")
        return ready_tasks



    def _is_task_ready(self, task_id: str) -> bool:
        """Check if a task is ready for execution

        Args:
            task_id: Task to check

        Returns:
            True if task is ready, False otherwise
        """
        if not self.dag or task_id not in self.dag.nodes():
            return False

        # Task must be in pending state
        if self.dag.nodes[task_id].get('status') != 'pending':
            return False

        # All predecessor tasks must be completed
        predecessors = list(self.dag.predecessors(task_id))
        for pred_id in predecessors:
            if self.dag.nodes[pred_id].get('status') != 'completed':
                return False

        return True

    def mark_task_submitted(self, task_id: str) -> bool:
        """Mark a task as submitted

        Args:
            task_id: Task to mark as submitted

        Returns:
            True if successful, False otherwise
        """
        return self._update_task_status(task_id, 'submitted')

    def mark_task_complete(self, task_id: str) -> bool:
        """Mark a task as completed

        Args:
            task_id: Task to mark as completed

        Returns:
            True if successful, False otherwise
        """
        return self._update_task_status(task_id, 'completed')

    def _update_task_status(self, task_id: str, status: str) -> bool:
        """Update task status

        Args:
            task_id: Task to update
            status: New status

        Returns:
            True if successful, False otherwise
        """
        if not self.dag or task_id not in self.dag.nodes():
            logger.error(f"Task {task_id} not found in DAG")
            return False

        try:
            # with self._lock:
            old_status = self.dag.nodes[task_id].get('status', 'unknown')
            self.dag.nodes[task_id]['status'] = status
            logger.debug(f"Task {task_id} status: {old_status} -> {status}")
            return True

        except Exception as e:
            logger.error(f"Failed to update task {task_id} status: {str(e)}")
            return False

    def is_dag_complete(self) -> bool:
        """Check if all tasks in the DAG are completed

        Returns:
            True if all tasks are completed, False otherwise
        """
        if not self.dag:
            return False

        with self._lock:
            for node_id in self.dag.nodes():
                if self.dag.nodes[node_id].get('status') != 'completed':
                    return False

        return True

    def get_task_status(self, task_id: str) -> Optional[str]:
        """Get status of a specific task

        Args:
            task_id: Task to check

        Returns:
            Task status or None if task not found
        """
        if not self.dag or task_id not in self.dag.nodes():
            return None

        with self._lock:
            return self.dag.nodes[task_id].get('status')

    def get_completed_task_count(self) -> int:
        """Get number of completed tasks

        Returns:
            Number of completed tasks
        """
        if not self.dag:
            return 0

        count = 0
        with self._lock:
            for node_id in self.dag.nodes():
                if self.dag.nodes[node_id].get('status') == 'completed':
                    count += 1

        return count

    def get_total_task_count(self) -> int:
        """Get total number of tasks

        Returns:
            Total number of tasks
        """
        return len(self.dag.nodes()) if self.dag else 0

    def get_dag_summary(self) -> Dict[str, Any]:
        """Get summary of DAG status

        Returns:
            Dictionary with DAG summary information
        """
        if not self.dag:
            return {"status": "no_dag"}

        status_counts = {}
        with self._lock:
            for node_id in self.dag.nodes():
                status = self.dag.nodes[node_id].get('status', 'unknown')
                status_counts[status] = status_counts.get(status, 0) + 1

        return {
            "total_nodes": len(self.dag.nodes()),
            "total_edges": len(self.dag.edges()),
            "status_counts": status_counts,
            "is_complete": self.is_dag_complete()
        }

    def visualize_dag_status(self) -> str:
        """Generate a visual representation of the DAG with current status

        Returns:
            String representation of the DAG with status indicators
        """
        if not self.dag:
            return "No DAG loaded"

        # Status symbols
        status_symbols = {
            'pending': '⏳',      # Not ready for execution
            'ready': '🟡',       # Ready for execution
            'submitted': '🔄',   # Being executed
            'completed': '✅',   # Completed
            'failed': '❌'       # Failed
        }

        # Get ready tasks to determine which pending tasks are actually ready
        ready_tasks = set(self.get_ready_tasks())

        with self._lock:
            # Build status summary
            status_counts = {}
            for node_id in self.dag.nodes():
                status = self.dag.nodes[node_id].get('status', 'pending')
                # Override status for ready tasks
                if status == 'pending' and node_id in ready_tasks:
                    status = 'ready'
                status_counts[status] = status_counts.get(status, 0) + 1

            # Create the visualization
            lines = []
            lines.append("")
            lines.append("🔍 DAG STATUS VISUALIZATION")
            lines.append("=" * 50)

            # Status summary
            lines.append(f"📊 Status Summary:")
            for status, count in sorted(status_counts.items()):
                symbol = status_symbols.get(status, '❓')
                lines.append(f"   {symbol} {status.capitalize()}: {count}")

            lines.append("")
            lines.append("🌳 DAG Structure with Status (Execution Flow: Leaves → Root):")

            # Find leaf nodes (nodes with no successors) - these execute first
            leaf_nodes = [n for n in self.dag.nodes() if self.dag.out_degree(n) == 0]

            if not leaf_nodes:
                lines.append("   No leaf nodes found")
                return "\n".join(lines)

            # Recursively build tree structure from leaves to root
            visited = set()
            for leaf in sorted(leaf_nodes):
                self._build_reverse_tree_visualization(leaf, lines, visited, ready_tasks, status_symbols, "")

            lines.append("")
            lines.append("Legend:")
            lines.append("   ⏳ Pending (dependencies not met)")
            lines.append("   🟡 Ready (can be executed)")
            lines.append("   🔄 Submitted (being executed)")
            lines.append("   ✅ Completed")
            lines.append("   ❌ Failed")
            lines.append("=" * 50)

        return "\n".join(lines)

    def _build_reverse_tree_visualization(self, node_id: str, lines: List[str], visited: Set[str],
                                        ready_tasks: Set[str], status_symbols: Dict[str, str], prefix: str):
        """Recursively build tree visualization showing execution flow from leaves to root

        Args:
            node_id: Current node to visualize
            lines: List to append visualization lines to
            visited: Set of already visited nodes
            ready_tasks: Set of ready task IDs
            status_symbols: Mapping of status to symbols
            prefix: Current indentation prefix
        """
        if node_id in visited:
            return

        visited.add(node_id)

        # Get node status
        status = self.dag.nodes[node_id].get('status', 'pending')
        if status == 'pending' and node_id in ready_tasks:
            status = 'ready'

        symbol = status_symbols.get(status, '❓')

        # Get node info
        node_data = self.dag.nodes[node_id]

        # Format node line (removed misleading timing information)
        node_line = f"{prefix}└── {symbol} {node_id}"
        lines.append(node_line)

        # Get parents (predecessors) - these execute after this node
        parents = list(self.dag.predecessors(node_id))
        parents.sort()  # Sort for consistent output

        # Recursively add parents
        for i, parent in enumerate(parents):
            is_last = (i == len(parents) - 1)
            parent_prefix = prefix + ("    " if is_last else "│   ")
            self._build_reverse_tree_visualization(parent, lines, visited, ready_tasks, status_symbols, parent_prefix)

    def _build_tree_visualization(self, node_id: str, lines: List[str], visited: Set[str],
                                ready_tasks: Set[str], status_symbols: Dict[str, str], prefix: str):
        """Recursively build tree visualization for a node and its children

        Args:
            node_id: Current node to visualize
            lines: List to append visualization lines to
            visited: Set of already visited nodes
            ready_tasks: Set of ready task IDs
            status_symbols: Mapping of status to symbols
            prefix: Current indentation prefix
        """
        if node_id in visited:
            return

        visited.add(node_id)

        # Get node status
        status = self.dag.nodes[node_id].get('status', 'pending')
        if status == 'pending' and node_id in ready_tasks:
            status = 'ready'

        symbol = status_symbols.get(status, '❓')

        # Get node info
        node_data = self.dag.nodes[node_id]
        task_type = node_data.get('task_type', 'unknown')

        # Add execution time if available
        exec_time = ""
        if 'worker_arguments' in node_data and len(node_data['worker_arguments']) >= 3:
            try:
                duration = int(node_data['worker_arguments'][2])
                exec_time = f" ({duration}ms)"
            except (ValueError, IndexError):
                pass

        # Format node line
        node_line = f"{prefix}└── {symbol} {node_id}{exec_time}"
        lines.append(node_line)

        # Get children (successors)
        children = list(self.dag.successors(node_id))
        children.sort()  # Sort for consistent output

        # Recursively add children
        for i, child in enumerate(children):
            is_last = (i == len(children) - 1)
            child_prefix = prefix + ("    " if is_last else "│   ")
            self._build_tree_visualization(child, lines, visited, ready_tasks, status_symbols, child_prefix)
