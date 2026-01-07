# Copyright 2024 Amazon.com, Inc. or its affiliates.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


"""
DAG Generator: Generate test DAGs with configurable structure
"""

import logging
import networkx as nx
import random
from typing import Dict, Any

logger = logging.getLogger("DAGGenerator")


class DAGGenerator:
    """Generates test DAGs with variable depth and breadth"""

    def __init__(self, dag_config: Dict[str, Any], seed: int = None):
        """Initialize DAG generator

        Args:
            dag_config: DAG-related configuration
            seed: Random seed for reproducible generation
        """
        self.config = dag_config
        if seed is not None:
            random.seed(seed)

        logger.debug("DAG Generator initialized")

    def generate_dag(self, depth: int, breadth: int) -> nx.DiGraph:
        """Generate a DAG with specified depth and breadth

        Args:
            depth: Number of levels in the DAG
            breadth: Maximum number of children per node

        Returns:
            Generated NetworkX DiGraph
        """
        if depth < 1:
            raise ValueError("Depth must be at least 1")
        if breadth < 1:
            raise ValueError("Breadth must be at least 1")

        logger.info(f"Generating DAG with depth={depth}, breadth={breadth}")

        dag = nx.DiGraph()
        node_counter = 0

        # Generate nodes level by level
        current_level = []

        for level in range(depth):
            next_level = []

            if level == 0:
                # Root level - create only 1 root node
                num_nodes = 1
                for i in range(num_nodes):
                    node_id = f"level_{level}_node_{i}"
                    task_type = "compute" if level == depth - 1 else "aggregation"

                    dag.add_node(
                        node_id,
                        task_type=task_type,
                        worker_arguments=self._generate_task_arguments(),
                        status="pending"
                    )
                    current_level.append(node_id)
                    node_counter += 1

                logger.debug(f"Level {level}: Created {len(current_level)} root nodes")
                # Don't set current_level = next_level for root level, keep the root nodes for next iteration
                continue
            else:
                # Create children for each node in current level
                if not current_level:
                    logger.debug(f"Level {level}: No parent nodes, stopping")
                    break

                for parent_node in current_level:
                    # Each parent gets 1 to breadth children
                    num_children = breadth
                    logger.debug(f"Level {level}: Creating {num_children} children for {parent_node}")

                    for i in range(num_children):
                        child_id = f"level_{level}_node_{node_counter}"
                        task_type = "compute" if level == depth - 1 else "aggregation"

                        dag.add_node(
                            child_id,
                            task_type=task_type,
                            worker_arguments=self._generate_task_arguments(),
                            status="pending"
                        )

                        # Add edge from child to parent (child must complete before parent)
                        dag.add_edge(child_id, parent_node)

                        next_level.append(child_id)
                        node_counter += 1

                logger.debug(f"Level {level}: Created {len(next_level)} child nodes")

            current_level = next_level

        # Validate generated DAG
        if not nx.is_directed_acyclic_graph(dag):
            logger.error("Generated graph contains cycles!")
            raise RuntimeError("Generated invalid DAG with cycles")

        logger.info(f"Generated DAG with {len(dag.nodes())} nodes and {len(dag.edges())} edges")

        # Log DAG statistics
        self._log_dag_statistics(dag)

        # Print DAG structure to stdout
        self._print_dag_structure(dag)

        return dag

    def _generate_task_arguments(self) -> list:
        """Generate random task arguments within specified ranges

        Returns:
            List of task arguments [param1, param2, param3]
        """
        sleep_ms = self.config.get("mock_tasks_sleep_time_ms", 100)
        param1 = str(sleep_ms)
        return [param1, "1", "1"]

    def _log_dag_statistics(self, dag: nx.DiGraph):
        """Log statistics about the generated DAG

        Args:
            dag: DAG to analyze
        """
        try:
            # Count node types
            compute_nodes = sum(1 for _, data in dag.nodes(data=True)
                                if data.get('task_type') == 'compute')
            aggregation_nodes = sum(1 for _, data in dag.nodes(data=True)
                                    if data.get('task_type') == 'aggregation')

            # Calculate depth (longest path)
            if dag.nodes():
                # Find nodes with no predecessors (roots)
                roots = [n for n in dag.nodes() if dag.in_degree(n) == 0]
                max_depth = 0

                for root in roots:
                    for node in dag.nodes():
                        if nx.has_path(dag, root, node):
                            try:
                                path_length = nx.shortest_path_length(dag, root, node)
                                max_depth = max(max_depth, path_length + 1)
                            except nx.NetworkXNoPath:
                                pass
            else:
                max_depth = 0

            logger.info("DAG Statistics:")
            logger.info(f"  Total nodes: {len(dag.nodes())}")
            logger.info(f"  Total edges: {len(dag.edges())}")
            logger.info(f"  Compute nodes: {compute_nodes}")
            logger.info(f"  Aggregation nodes: {aggregation_nodes}")
            logger.info(f"  Actual depth: {max_depth}")

        except Exception as e:
            logger.warning(f"Failed to calculate DAG statistics: {str(e)}")

    def _print_dag_structure(self, dag: nx.DiGraph):
        """Print DAG structure in a tree-like format showing execution flow

        Args:
            dag: DAG to visualize
        """
        print("\n" + "🌳 DAG STRUCTURE")
        print("=" * 50)

        if not dag.nodes():
            print("📭 Empty DAG")
            return

        # Find leaf nodes (no outgoing edges) - these execute first
        leaf_nodes = [n for n in dag.nodes() if dag.out_degree(n) == 0]
        # Find root node (should be level_0_node_0)
        root_nodes = [n for n in dag.nodes() if n.startswith('level_0_')]

        # Print summary
        total_nodes = len(dag.nodes())
        total_edges = len(dag.edges())
        print(f"📊 Summary: {total_nodes} nodes, {total_edges} edges")
        print(f"🎯 Execution: {len(leaf_nodes)} leaf nodes → 1 root node")
        print()

        # Show the tree structure from root down (logical structure)
        if root_nodes:
            root_node = root_nodes[0]  # Should be level_0_node_0
            print("🌱 DAG Tree (Root → Leaves):")
            visited = set()
            self._print_dependency_tree(dag, root_node, "", True, visited)
            print()

        print("⚡ Execution Order (leaf nodes execute first):")
        # Group nodes by level for execution order display
        levels = self._get_execution_levels(dag)
        for level_num, level_nodes in enumerate(levels):
            level_nodes_sorted = sorted(level_nodes)
            if level_num == 0:
                print(f"  Level {level_num + 1} (Execute First): {level_nodes_sorted}")
            elif level_num == len(levels) - 1:
                print(f"  Level {level_num + 1} (Execute Last):  {level_nodes_sorted}")
            else:
                print(f"  Level {level_num + 1}:                 {level_nodes_sorted}")

        print("=" * 50)
        print()

    def _print_dependency_tree(self, dag: nx.DiGraph, node: str, prefix: str, is_last: bool, visited: set):
        """Print dependency tree from root to leaves

        Args:
            dag: The DAG
            node: Current node to print
            prefix: Current line prefix for indentation
            is_last: Whether this is the last child at this level
            visited: Set of already visited nodes
        """
        if node in visited:
            return
        visited.add(node)

        # Get node info
        node_data = dag.nodes[node]
        task_type = node_data.get('task_type', 'unknown')
        worker_args = node_data.get('worker_arguments', [])
        exec_time = worker_args[0] if worker_args else "?"

        # Choose appropriate symbols
        connector = "└── " if is_last else "├── "
        type_icon = "🔄" if task_type == "aggregation" else "⚡"

        # Print current node
        print(f"{prefix}{connector}{type_icon} {node} ({exec_time}ms)")

        # Get dependencies (nodes that must complete before this one)
        dependencies = sorted(list(dag.predecessors(node)))

        # Print dependencies
        for i, dep in enumerate(dependencies):
            is_dep_last = (i == len(dependencies) - 1)
            dep_prefix = prefix + ("    " if is_last else "│   ")
            self._print_dependency_tree(dag, dep, dep_prefix, is_dep_last, visited)

    def _get_execution_levels(self, dag: nx.DiGraph):
        """Get nodes grouped by execution level (topological sort levels)

        Args:
            dag: The DAG to analyze

        Returns:
            List of lists, where each inner list contains nodes at that execution level
        """
        # Create a copy to avoid modifying original
        dag_copy = dag.copy()
        levels = []

        while dag_copy.nodes():
            # Find nodes with no incoming edges (ready to execute)
            ready_nodes = [n for n in dag_copy.nodes() if dag_copy.in_degree(n) == 0]

            if not ready_nodes:
                # Should not happen in a valid DAG
                break

            levels.append(ready_nodes)

            # Remove these nodes and their edges
            dag_copy.remove_nodes_from(ready_nodes)

        return levels

    def _print_tree_recursive(self, dag: nx.DiGraph, node: str, prefix: str, is_last: bool, visited: set):
        """Recursively print tree structure

        Args:
            dag: The DAG
            node: Current node to print
            prefix: Current line prefix for indentation
            is_last: Whether this is the last child at this level
            visited: Set of already visited nodes
        """
        if node in visited:
            return
        visited.add(node)

        # Get node info
        node_data = dag.nodes[node]
        task_type = node_data.get('task_type', 'unknown')
        worker_args = node_data.get('worker_arguments', [])
        exec_time = worker_args[0] if worker_args else "?"

        # Choose appropriate symbols
        connector = "└── " if is_last else "├── "
        type_icon = "🔄" if task_type == "aggregation" else "⚡"

        # Print current node
        print(f"{prefix}{connector}{type_icon} {node} ({exec_time}ms)")

        # Get children
        children = sorted(list(dag.successors(node)))

        # Print children
        for i, child in enumerate(children):
            is_child_last = (i == len(children) - 1)
            child_prefix = prefix + ("    " if is_last else "│   ")
            self._print_tree_recursive(dag, child, child_prefix, is_child_last, visited)

    def generate_linear_dag(self, num_tasks: int) -> nx.DiGraph:
        """Generate a linear DAG (chain of tasks)

        Args:
            num_tasks: Number of tasks in the chain

        Returns:
            Linear DAG
        """
        logger.info(f"Generating linear DAG with {num_tasks} tasks")

        dag = nx.DiGraph()

        for i in range(num_tasks):
            task_id = f"task_{i}"
            task_type = "compute"  # All tasks are compute tasks in linear chain

            dag.add_node(
                task_id,
                task_type=task_type,
                worker_arguments=self._generate_task_arguments(),
                status="pending"
            )

            # Add edge from previous task
            if i > 0:
                dag.add_edge(f"task_{i - 1}", task_id)

        logger.info(f"Generated linear DAG with {len(dag.nodes())} nodes and {len(dag.edges())} edges")
        return dag

    def generate_fan_out_dag(self, num_leaf_tasks: int) -> nx.DiGraph:
        """Generate a fan-out DAG (one root with multiple children)

        Args:
            num_leaf_tasks: Number of leaf tasks

        Returns:
            Fan-out DAG
        """
        logger.info(f"Generating fan-out DAG with {num_leaf_tasks} leaf tasks")

        dag = nx.DiGraph()

        # Add root task
        root_id = "root_task"
        dag.add_node(
            root_id,
            task_type="aggregation",
            worker_arguments=self._generate_task_arguments(),
            status="pending"
        )

        # Add leaf tasks
        for i in range(num_leaf_tasks):
            leaf_id = f"leaf_task_{i}"
            dag.add_node(
                leaf_id,
                task_type="compute",
                worker_arguments=self._generate_task_arguments(),
                status="pending"
            )

            # Add edge from root to leaf
            dag.add_edge(root_id, leaf_id)

        logger.info(f"Generated fan-out DAG with {len(dag.nodes())} nodes and {len(dag.edges())} edges")
        return dag
