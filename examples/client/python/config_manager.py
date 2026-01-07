#!/usr/bin/env python3
"""
HTC-Client-DAG: Main client application for processing DAGs using HTC Grid.
Refactored to expose functional API instead of a monolithic class.
"""

import json
import os
import logging
from typing import Dict, Any, Optional

logger = logging.getLogger("ConfigManager")

class ConfigManager:
    """Manages system configuration loading and validation"""
    def __init__(self, config_file: Optional[str] = None) -> None:
        """Initialize configuration manager

        Args:
            config_file: Path to configuration file
        """

        self.config = self._load_config(config_file)
        logger.info(f"Configuration loaded from {config_file}")

    def _load_config(self, config_file: str) -> Dict[str, Any]:
        """Load configuration from file and apply overrides.

        Returns:
            Configuration dictionary
        """
        if not config_file:
            raise ValueError("config_file is required to load configuration")

        if not os.path.exists(config_file):
            raise FileNotFoundError(f"Config file {config_file} not found")

        try:
            with open(config_file, 'r') as f:
                config = json.load(f)
            logger.info(f"Loaded configuration from {config_file}")
        except Exception as e:
            raise ValueError(f"Failed to load config file {config_file}: {e}") from e

        # Override with environment variables
        self._apply_environment_overrides(config)

        return config

    def _apply_environment_overrides(self, config: Dict[str, Any]) -> None:
        """Apply environment variable overrides

        Args:
            config: Configuration dictionary to update
        """
        # HTC Grid configuration from environment
        if "AGENT_CONFIG_FILE" in os.environ:
            config["htc_grid"]["client_config_file"] = os.environ["AGENT_CONFIG_FILE"]

        if "USERNAME" in os.environ:
            config["htc_grid"]["username"] = os.environ["USERNAME"]

        if "PASSWORD" in os.environ:
            config["htc_grid"]["password"] = os.environ["PASSWORD"]

        # Other environment overrides
        if "HTC_USE_MOCK" in os.environ:
            config["use_mock_grid"] = os.environ["HTC_USE_MOCK"].lower() in ('true', '1', 'yes')

        if "HTC_POLLING_INTERVAL" in os.environ:
            try:
                config["polling_interval_seconds"] = int(os.environ["HTC_POLLING_INTERVAL"])
            except ValueError:
                logger.warning("Invalid HTC_POLLING_INTERVAL value, ignoring")

        if "HTC_BATCH_SIZE" in os.environ:
            try:
                config["batch_size"] = int(os.environ["HTC_BATCH_SIZE"])
            except ValueError:
                logger.warning("Invalid HTC_BATCH_SIZE value, ignoring")


    def get_config(self) -> Dict[str, Any]:
        """Get current configuration

        Returns:
            Configuration dictionary
        """
        return self.config.copy()

    def get(self, key: str, default: Any = None) -> Any:
        """Retrieve a config value by key with an optional default."""
        return self.config.get(key, default)

    def set(self, key: str, value: Any) -> None:
        """
        Set a configuration key to a new value without validation.

        Useful for tests or runtime overrides; callers should validate as needed.
        """
        self.config[key] = value

    def update_config(self, updates: Dict[str, Any]) -> bool:
        """Update configuration with new values

        Args:
            updates: Dictionary of configuration updates

        Returns:
            True if update successful, False otherwise
        """
        try:
            # Create updated configuration
            new_config = self.config.copy()
            new_config.update(updates)

            # Validate updated configuration
            if not self._validate_config(new_config):
                logger.error("Configuration update validation failed")
                return False

            self.config = new_config
            logger.info("Configuration updated successfully")
            return True

        except Exception as e:
            logger.error(f"Failed to update configuration: {str(e)}")
            return False

    def get_htc_config(self) -> Dict[str, Any]:
        """Get HTC grid specific configuration

        Returns:
            HTC grid configuration dictionary
        """
        return self.config.get("htc_grid", {}).copy()
