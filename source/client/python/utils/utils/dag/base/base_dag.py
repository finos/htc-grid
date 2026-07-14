# Copyright 2024 Amazon.com, Inc. or its affiliates.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

"""
Base DAG abstraction used by the DAG processor.

This skeleton aligns with the DDD design in DDD.md: it defines the stable
contract that domain-specific DAG adapters must implement so the processor
can reason about ready nodes, mark progress, and detect completion without
depending on any concrete DAG library.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any, Dict, Hashable, Iterable


class BaseDAG(ABC):
    """Minimal DAG contract for the processor to interact with domain DAGs."""

    @abstractmethod
    def get_nodes_with_resolved_dependencies(self) -> Iterable[Hashable]:
        """
        Return an iterable of node identifiers whose dependencies are fully satisfied
        and are ready for execution/submission.
        """

    @abstractmethod
    def mark_node_completed(self, node_id: Hashable) -> None:
        """
        Mark the given node as completed so downstream dependency checks can be updated.
        """

    @abstractmethod
    def is_dag_completed(self) -> bool:
        """
        Return True when all nodes have been processed/completed, otherwise False.
        """

    @abstractmethod
    def get_node_by_id(self, node_id: Hashable):
        """
        Return the node object/data for the given node identifier.

        Args:
            node_id: The identifier of the node to retrieve

        Returns:
            The node object or data associated with the given ID, or None if not found

        """

    @abstractmethod
    def build_grid_task(self, node_id: Hashable) -> Dict[str, Any]:
        """
        Build and return a grid connector task definition for the given DAG node.

        The returned object must be suitable to pass to the grid connector `send()` call.
        """
