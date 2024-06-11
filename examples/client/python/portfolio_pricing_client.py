# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

from api.connector import AWSConnector

import os
import json
import random
import logging
import argparse

try:
    client_config_file = os.environ["AGENT_CONFIG_FILE"]
except:
    client_config_file = "/etc/agent/Agent_config.tfvars.json"

with open(client_config_file, "r") as file:
    client_config_file = json.loads(file.read())


class PortfolioGenerator:
    """
    A simple portfolio generator that builds a portfolio of trades based on a list of existing trades (seed_trades).
    PortfolioGenerator randomly select one of the known trades and puts it into generated portfolio. Duplicates may occur.
    """

    def __init__(self, config=None):
        if config is None:
            self.config = {"portfolio_target_size": 1}
        else:
            self.config = config

        with open("sample_portfolio.json") as json_file:
            self.seed_portfolio = json.load(json_file)

    def generate_portfolio(self):
        portfolio = []

        seed_range = len(self.seed_portfolio["portfolio"])

        for i in range(0, self.config["portfolio_target_size"]):
            index = random.randint(0, seed_range - 1)

            portfolio.append(self.seed_portfolio["portfolio"][index])

        return {"portfolio": portfolio}


def get_sample_portfolio():
    return {
        "portfolio": [
            {
                "tradeType": "option",
                "exercise": "European",
                "engineName": "AnalyticEuropeanEngine",
                "engineParameters": {},
                "tradeParameters": {
                    "evaluationDate": "15 5 1998",
                    "exerciseDate": "17 5 1999",
                    "payoff": 8.0,
                    "underlying": 7.0,
                    "dividendYield": 0.05,
                    "volatility": 0.10,
                    "riskFreeRate": 0.05,
                },
            }
        ]
    }


def split_portfolio_into_tasks(portfolio):
    """It is common to split a large portfolio among multiple workers.
    This function is a simple example where portfolio is divided into mini-batches of the fixed number of trades in each to evaluate.
    In production a more complicated logic might be used.

    Args:
        portfolio: dict

    Returns:
        list of lists

    """

    batch_size = FLAGS.trades_per_worker
    trades_list = portfolio["portfolio"]
    tasks_batches = [
        trades_list[x: x + batch_size] for x in range(0, len(trades_list), batch_size)
    ]

    grid_tasks = []

    for workers_batch in tasks_batches:
        grid_task = {"portfolio": []}
        for trade in workers_batch:
            grid_task["portfolio"].append(trade)
        grid_tasks.append(grid_task)

    return grid_tasks


def evaluate_trades_on_grid(grid_tasks):
    """This method simply passes the list of grid_tasks to the grid for the execution and then awaits the results

    Args:
        grid_tasks (list of dict) grid_tasks

    Returns:
        dict: final response from the get_results function

    """

    gridConnector = AWSConnector()

    try:
        username = os.environ["USERNAME"]
    except KeyError:
        username = ""
    try:
        password = os.environ["PASSWORD"]
    except KeyError:
        password = ""  # nosec B105

    gridConnector.init(client_config_file, username=username, password=password)  # nosec B105
    gridConnector.authenticate()

    submission_resp = gridConnector.send(grid_tasks)
    logging.info(submission_resp)

    results = gridConnector.get_results(submission_resp, timeout_sec=FLAGS.timeout_sec)
    logging.info(results)

    return results


def merge_results(sample_portfolio, grid_results):
    """This function merges multiple results from the grid.

    Args:
        str: sample_portfolio - initial list of tasks
        str: grid_results - response from the get_results function. Expected output is demonstrated below.
        The actual output will depend on the implementation of the worker lambda function
        {
            "finished": [
                "ea59c0dc-ab53-11eb-ad40-16e8133b0d08-part005_4",
                "ea59c0dc-ab53-11eb-ad40-16e8133b0d08-part005_5",
                ...
            ],
            "finished_OUTPUT": [
                "{"results": [0.030341803941731974]}",
                "{"results": [4.489065538706168]}",
                ...
            ],
            "metadata": { "tasks_in_response": 10 }
            }

    Returns:
        number: total value of the evaluated portfolio.

    """

    logging.info(grid_results)

    portfolio_value = 0.0

    for str_output in grid_results["finished_OUTPUT"]:
        json_out = json.loads(str_output)
        logging.info(json_out)

        for val in json_out["results"]:
            portfolio_value += val

    return portfolio_value


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        """ An example of a client application that receives/generates a portfolio of trades
        and evaluates """,
        add_help=True,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )

    parser.add_argument(
        "--workload_type",
        type=str,
        default="single_trade",
        choices=["single_trade", "random_portfolio"],
        help="""Determines how tasks are being generated.""",
    )

    parser.add_argument(
        "--trades_per_worker",
        type=int,
        default=1,
        help="""Defines how many tasks/trades each worker will evaluate (i.e., batching per worker)
                                For example if we have 5 trades and trades per worker set to 2,
                                then we have total number of tasks equal to 3: [1,2] [3,4] [5]""",
    )

    parser.add_argument(
        "--portfolio_size",
        type=int,
        default=10,
        help="Override the size of the sample portfolio",
    )

    parser.add_argument(
        "--timeout_sec",
        type=int,
        default=120,
        help="How long to wait for all results to be completed.",
    )

    FLAGS = parser.parse_args()

    sample_portfolio = None

    # <1.> Generate a sample portfolio that we intend to evaluate.
    logging.info("1. Generating sample portfolio...")

    if FLAGS.workload_type == "single_trade":
        sample_portfolio = get_sample_portfolio()

    elif FLAGS.workload_type == "random_portfolio":
        configuration = {"portfolio_target_size": FLAGS.portfolio_size}

        pg = PortfolioGenerator(configuration)

        sample_portfolio = pg.generate_portfolio()

        logging.info(sample_portfolio)

    # <2.> Split portfolio into tasks that will be sent to HTC-Grid for the evaluation.
    logging.info("2. Splitting portfolio into sub-tasks")
    grid_tasks = split_portfolio_into_tasks(sample_portfolio)

    # <3.> Submit tasks to the HTC-Grid
    logging.info("3. Connecting to the grid and submitting tasks")
    grid_results = evaluate_trades_on_grid(grid_tasks)

    # <4.> Merge results to evaluate value of the portfolio
    portfolio_value = merge_results(sample_portfolio, grid_results)
    logging.info(f"Portfolio value: {portfolio_value}")
