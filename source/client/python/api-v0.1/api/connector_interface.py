# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

from abc import ABC, abstractmethod
from typing import Dict, List, Any, Optional

class GridConnectorInterface(ABC):
    """Abstract interface for grid connectors"""

    @abstractmethod
    def init(self, config: Dict[str, Any]) -> None:
        """Initialize the grid connector

        Args:
            config: Configuration dictionary
        """
        pass

    @abstractmethod
    def authenticate(self) -> None:
        """Authenticate with the grid"""
        pass

    @abstractmethod
    def send(self, task_vector: List[Dict[str, Any]]) -> str:
        """Submit a vector of tasks to the grid

        Args:
            task_vector: List of task definitions

        Returns:
            Submission response object for tracking
        """
        pass

    @abstractmethod
    def get_results(self, submission_resp: str, timeout_sec: Optional[int] = None) -> Optional[Dict[str, Any]]:
        """Get results for a specific submission

        Args:
            submission_resp: Submission response object from send()
            timeout_sec: Maximum wait time in seconds (0 for non-blocking check)

        Returns:
            Results if complete, None if still in progress
        """
        pass
