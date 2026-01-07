# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import argparse
import json
import logging
from pathlib import Path

import networkx as nx
from networkx.readwrite import json_graph


class BusinessDagLoader:
    """Loads a DAG file into a NetworkX DiGraph.

    Currently supports NetworkX node-link JSON.
    """

    def __init__(self, copies: int = 1) -> None:
        if copies < 1:
            raise ValueError("copies must be >= 1")
        self._copies = copies
        self._logger = logging.getLogger(self.__class__.__name__)

    def load(self, path: str) -> nx.DiGraph:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        return self.loads(data)

    def loads(self, data: object) -> nx.DiGraph:
        if not isinstance(data, dict):
            raise ValueError("Invalid JSON: expected an object at the root")

        if "edges" in data:
            edges_key = "edges"
        elif "links" in data:
            edges_key = "links"
        else:
            raise ValueError("Invalid node-link JSON: expected 'edges' or 'links' key")

        graph = json_graph.node_link_graph(data, link=edges_key)

        digraph = nx.DiGraph(graph)
        for _, node_data in digraph.nodes(data=True):
            node_data.setdefault("task_type", "compute")
            node_data.setdefault("worker_arguments", ["1000", "1", "1"])

        if self._copies > 1:
            return self._replicate_dag(digraph, copies=self._copies)

        return digraph

    def _replicate_dag(self, nx_dag: nx.DiGraph, copies: int, super_root: str = "SUPER_ROOT") -> nx.DiGraph:
        """
        Create a new DAG composed of `copies` disjoint copies of the input DAG, all
        attached beneath a new super-root node.

        Each copy's nodes are prefixed with an index (`0_`, `1_`, ...) to keep names unique.
        The super-root is connected to one root of each copy (root with the highest out-degree).
        """
        if copies < 1:
            raise ValueError("copies must be >= 1")
        if nx_dag.number_of_nodes() == 0:
            raise ValueError("input DAG is empty")

        roots = [n for n in nx_dag.nodes() if nx_dag.in_degree(n) == 0]

        if not roots:
            raise ValueError("input DAG has no roots (graph may contain cycles)")

        # Choose the root with the highest out_degree.
        first_root = max(roots, key=lambda n: nx_dag.out_degree(n))
        self._logger.debug(
            "Selected root with max out_degree: %s (out_degree=%s)",
            first_root,
            nx_dag.out_degree(first_root),
        )

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


def main() -> int:
    parser = argparse.ArgumentParser(description="Load a NetworkX node-link JSON file into a DiGraph.")
    parser.add_argument("path", nargs="?", default="morse_trie_networkx.json", help="Path to node-link JSON file")
    args = parser.parse_args()

    path = Path(args.path)
    graph = BusinessDagLoader().load(path)

    print(f"Loaded graph type: {type(graph).__name__}")
    print(f"Nodes: {graph.number_of_nodes()}, Edges: {graph.number_of_edges()}")
    if "" in graph:
        print("Root node '' present: yes")
    else:
        print("Root node '' present: no")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
