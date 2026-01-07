# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import argparse
import json
from pathlib import Path

import networkx as nx
from networkx.readwrite import json_graph


class BusinessDagLoader:
    """Loads a DAG file into a NetworkX DiGraph.

    Currently supports NetworkX node-link JSON.
    """

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
        return digraph


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
