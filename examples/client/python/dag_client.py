#!/usr/bin/env python3
"""
HTC-Client-DAG: Main client application for processing DAGs using HTC Grid.
Refactored to expose functional API instead of a monolithic class.
"""

import argparse
import json
import logging
import os
import sys
import pickle
from typing import Any, Dict, Optional

import networkx as nx

from config_manager import ConfigManager
from utils.dag.base.dag_generator import DAGGenerator
from utils.dag.base.nx_htc_dag_container import NxHtcDagContainer
from business_dag_loader import BusinessDagLoader

from api.connector import AWSConnector
from api.mock_connector import MockGridConnector

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
    # lg.setLevel(getattr(logging, log_level.upper(), logging.DEBUG))
    # # Ensure stdout handler is attached even if basicConfig was a no-op
    # if not any(isinstance(h, logging.StreamHandler) for h in lg.handlers):
    #     stdout_handler = logging.StreamHandler(sys.stdout)
    #     stdout_handler.setLevel(getattr(logging, log_level.upper(), logging.DEBUG))
    #     formatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
    #     stdout_handler.setFormatter(formatter)
    #     lg.addHandler(stdout_handler)
    return lg


logger = logging.getLogger("HTCClientDAG")

try:
    client_config_file = os.environ["AGENT_CONFIG_FILE"]
except:
    client_config_file = "/etc/agent/Agent_config.tfvars.json"




def replicate_dag(nx_dag: nx.DiGraph, copies: int = 2, super_root: str = "SUPER_ROOT") -> nx.DiGraph:
    """
    Create a new DAG composed of `copies` disjoint copies of the input DAG, all
    attached beneath a new super-root node.

    Each copy's nodes are prefixed with an index (`0_`, `1_`, ...) to keep names unique.
    The super-root is connected to one root of each copy (first node in topological order).
    """
    if copies < 1:
        raise ValueError("copies must be >= 1")
    if nx_dag.number_of_nodes() == 0:
        raise ValueError("input DAG is empty")

    # Find a representative root (first in topological order) to attach under super-root
    # first_root = next(iter(nx.topological_sort(nx_dag)), None)


    roots = [n for n in nx_dag.nodes() if nx_dag.in_degree(n) == 0]
    # for r in roots:
    #     print(f"Node {r}: out={nx_dag.out_degree(r)} in={nx_dag.in_degree(r)}")

    # Choose the root with the highest out_degree (fall back to None)
    first_root = max(roots, key=lambda n: nx_dag.out_degree(n), default=None)
    print("First root (max out_degree):", first_root, nx_dag.out_degree(first_root))


    if first_root is None:
        raise ValueError("input DAG has no nodes")



    combined = nx.DiGraph()
    combined.add_node(super_root)

    combined.nodes[super_root]["task_type"] = "compute"
    combined.nodes[super_root]["worker_arguments"] = ["1", "1", "1"]

    for idx in range(copies):
        mapping = {node: f"{idx}_{node}" for node in nx_dag.nodes()}
        copy_graph = nx.relabel_nodes(nx_dag, mapping, copy=True)
        combined.update(copy_graph)
        combined.add_edge(super_root, mapping[first_root])

    return combined


def init_grid_connector(config_manager: ConfigManager) -> Any:
    """
    Initialize and return a client context namespace with bound helper functions.
    This replaces the old HTCClientDAG class.
    """
    logger.info("Initializing HTC Grid Client")


    # Initialize DAG manager
    dag_manager = NxHtcDagContainer()

    # Initialize grid connector based on configuration
    if config_manager.get("use_mock_grid", False):
        logger.info("Using Mock Grid Connector for local testing")
        grid_connector = MockGridConnector()
        grid_connector.init(config_manager.get("htc_grid", []) )
    else:
        logger.info("Using HTC Grid Connector for production")
        grid_connector = AWSConnector()


        with open(client_config_file, "r") as file:
            client_config_json = json.loads(file.read())
            grid_connector.init(client_config_json)



    # Initialize grid connector



    grid_connector.authenticate()

    return grid_connector

def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(description="HTC-Client-DAG: Process DAGs using HTC Grid")
    parser.add_argument("--config", default="config/config.json", help="Path to configuration file")
    parser.add_argument("--mock", action="store_true", help="Use mock grid connector")
    parser.add_argument("--generate", action="store_true", help="Generate test DAG")
    parser.add_argument("--depth", type=int, default=3, help="DAG depth for generation")
    parser.add_argument("--breadth", type=int, default=2, help="DAG breadth for generation")
    parser.add_argument("--dag-file", help="Load DAG from file")
    parser.add_argument("--visualize", action="store_true", help="Show DAG visualization during execution")
    parser.add_argument("--copies", type=int, default=1, help="Number of DAG copies to create")

    args = parser.parse_args()

    try:

        config_manager = ConfigManager(args.config)
        config = config_manager.get_config()


        global logger
        logger = setup_logging(config.get("log_level", "INFO"))

        if args.visualize:
            config_manager.set("show_dag_visualization", True)

        if args.mock:
            config_manager.set("use_mock_grid", True)
            config["use_mock_grid"] = True
            logger.info("Using mock grid connector for local testing")


        grid_connector = init_grid_connector(config_manager)

        nx_dag = None
        if args.generate:
            nx_dag = DAGGenerator(config).generate_dag(args.depth, args.breadth)

        elif args.dag_file:


            nx_dag = BusinessDagLoader().load(args.dag_file)


            if args.copies > 1:
                nx_dag=replicate_dag(nx_dag, copies=args.copies)

        else:
            raise ValueError("Must specify either --generate or --dag-file")



        print("STATISTICS----------------------------------START")
        print(f"Nodes: {nx_dag.number_of_nodes()}, Edges: {nx_dag.number_of_edges()}")
        data = pickle.dumps(nx_dag)
        print(f"Pickled NetworkX DiGraph size: {len(data) / 1_000_000:.2f} MB ({len(data)} bytes)")
        print("STATISTICS----------------------------------END")


        nx_dag_container = NxHtcDagContainer(nx_dag)

        adapter = GridConnectorDagAdapter(config, logger, grid_connector=None)
        try:
            scheduler = HTCDagScheduler(
                config=config,
                dag_container=nx_dag_container,
                grid_connector_adapter=adapter,
                grid_connector=None,
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
