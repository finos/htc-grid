# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

from api.connector import AWSConnector

import os
import json
import time
import argparse

try:
    client_config_file = os.environ["AGENT_CONFIG_FILE"]
except:
    client_config_file = "/etc/agent/Agent_config.tfvars.json"

with open(client_config_file, "r") as file:
    client_config_file = json.loads(file.read())


def get_construction_arguments():
    parser = argparse.ArgumentParser(
        """ Sample client, demonstrates job cancillation logic.
        For accurate tests make sure that only 1 worker lambda function is running
        and task queue is empty. """,
        add_help=True,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )

    parser.add_argument(
        "--test_cancel_many_small_tasks",
        type=bool,
        default=False,
        help="Many small tasks are launched and then entire session is cancelled.",
    )

    parser.add_argument(
        "--test_cancel_one_long_task",
        type=bool,
        default=False,
        help="One long running task cancelled during the execution.",
    )

    return parser


if __name__ == "__main__":
    FLAGS = get_construction_arguments().parse_args()

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

    if FLAGS.test_cancel_many_small_tasks:
        task_definition = {"worker_arguments": ["1000", "1", "1"]}

        # Submit 10 tasks
        submission_resp = gridConnector.send([task_definition for x in range(0, 10)])
        print(submission_resp)

        # Wait for some tasks to be completed
        time.sleep(2)

        print("Sending cancellation...")

        # Cancel all remaining tasks
        cancel_resp = gridConnector.cancel_sessions([submission_resp["session_id"]])
        print(cancel_resp)

        results = gridConnector.get_results(submission_resp, timeout_sec=10)
        print(results)

    elif FLAGS.test_cancel_one_long_task:
        task_definition = {"worker_arguments": ["120000", "1", "1"]}

        submission_resp = gridConnector.send([task_definition])
        print(submission_resp)

        # Wait for some time to make sure that agent picked that task.
        time.sleep(30)

        print("Send cancellation...")
        # Cancel the tasks
        cancel_resp = gridConnector.cancel_sessions([submission_resp["session_id"]])
        print(cancel_resp)
