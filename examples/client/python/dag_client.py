# Copyright 2024 Amazon.com, Inc. or its affiliates.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

# HTC-Client-DAG: Main client application for processing DAGs using HTC Grid.

import argparse
import json
import logging
import os
import sys
import pickle

from utils.dag.base.dag_generator import DAGGenerator
from utils.dag.base.nx_htc_dag_container import NxHtcDagContainer
from business_dag_loader import BusinessDagLoader

from utils.dag.schedulers.htc_dag_scheduler import HTCDagScheduler
from utils.dag.adapters.grid_connector_dag_adapter import GridConnectorDagAdapter


def setup_logging(log_level: str = "DEBUG") -> logging.Logger:
    """Setup logging configuration and return the module logger."""
    logging.basicConfig(
        level=getattr(logging, log_level.upper(), logging.DEBUG),
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
        handlers=[logging.StreamHandler(sys.stdout)],
    )
    lg = logging.getLogger("HTCClientDAG")

    return lg


logger = logging.getLogger("HTCClientDAG")


def load_config(config_file: str) -> dict:
    if not config_file:
        raise ValueError("config_file is required to load configuration")
    if not os.path.exists(config_file):
        raise FileNotFoundError(f"Config file {config_file} not found")
    try:
        with open(config_file, "r", encoding="utf-8") as file:
            return json.load(file)
    except Exception as exc:
        raise ValueError(f"Failed to load config file {config_file}: {exc}") from exc


def main() -> int:

    parser = argparse.ArgumentParser(description="HTC-Client-DAG: Process DAGs using HTC Grid")
    parser.add_argument("--config", default="config/config.json", help="Path to configuration file")
    parser.add_argument("--mock", action="store_true", help="Use mock grid connector")
    parser.add_argument("--generate", action="store_true", help="Generate test DAG.")
    parser.add_argument("--depth", type=int, default=3, help="DAG depth for generation.")
    parser.add_argument("--breadth", type=int, default=2, help="DAG breadth for generation.")
    parser.add_argument("--dag-file", help="Load DAG from a file, format must match business dag loader.")
    parser.add_argument("--visualize", action="store_true", help="Show DAG visualization during execution (for small scale tests only).")
    parser.add_argument("--copies", type=int, default=1, help="Replicates input DAG from the file for large scale tests.")

    args = parser.parse_args()

    try:

        config = load_config(args.config)


        global logger
        logger = setup_logging(config.get("log_level", "INFO"))
        logger.info("Configuration loaded from %s", args.config)

        if args.visualize:
            config["show_dag_visualization"] = True

        if args.mock:
            config["use_mock_grid"] = True
            logger.info("Using mock grid connector for local testing")

        nx_dag = None
        if args.generate:
            nx_dag = DAGGenerator(config).generate_dag(args.depth, args.breadth)
        elif args.dag_file:
            nx_dag = BusinessDagLoader(copies=args.copies).load(args.dag_file)
        else:
            raise ValueError("Must specify either --generate or --dag-file")



        logger.info("DAG STATISTICS:")
        logger.info("Nodes: %s, Edges: %s", nx_dag.number_of_nodes(), nx_dag.number_of_edges())
        data = pickle.dumps(nx_dag)
        logger.info(
            "Pickled NetworkX DiGraph size: %.2f MB (%s bytes)",
            len(data) / 1_000_000,
            len(data),
        )

        nx_dag_container = NxHtcDagContainer(nx_dag)

        adapter = GridConnectorDagAdapter(config, logger)

        try:
            scheduler = HTCDagScheduler(
                config=config,
                dag_container=nx_dag_container,
                grid_connector_adapter=adapter,
            )

            # Process DAG
            success = scheduler.run()
            return 0 if success else 1
        finally:
            try:
                adapter.shutdown(wait=True, timeout=float(config.get("shutdown_timeout_sec", 10.0)))
            except Exception:
                logger.exception("Failed to shutdown threaded adapter cleanly")

    except Exception as e:
        logger.error(f"Application failed: {str(e)}", exc_info=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
