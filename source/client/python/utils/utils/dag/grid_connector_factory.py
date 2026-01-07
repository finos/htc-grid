"""
Grid connector factories.

This module isolates connector construction/authentication logic from adapters.
"""

from __future__ import annotations

import json
import logging
from typing import Any, Dict, Protocol


class BaseGridConnectorFactory(Protocol):
    def create(self, thread_id: int, logger: logging.Logger) -> Any: ...


class GridConnectorFactory:
    """Default connector factory based on adapter config."""

    def __init__(self, config: Dict[str, Any], prototype_connector: Any = None) -> None:
        self._config = config
        self._prototype_connector = prototype_connector

    def create(self, thread_id: int, logger: logging.Logger) -> Any:
        import os

        use_mock = bool(self._config.get("use_mock_grid", False))

        if use_mock:
            from api.mock_connector import MockGridConnector

            connector = MockGridConnector()
            connector.init(self._config.get("htc_grid", []))
            connector.authenticate()
            return connector

        try:
            client_config_file = os.environ["AGENT_CONFIG_FILE"]
        except KeyError:
            client_config_file = "/etc/agent/Agent_config.tfvars.json"

        if self._prototype_connector is not None:
            connector_cls = self._prototype_connector.__class__
            connector = connector_cls()
        else:
            from api.connector import AWSConnector

            connector = AWSConnector()

        with open(client_config_file, "r") as file:
            client_config_json = json.loads(file.read())
            connector.init(client_config_json)

        connector.authenticate()
        logger.debug(f"Thread {thread_id}: connector authenticated")
        return connector

