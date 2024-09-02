# Copyright 2022 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

from api.connector import AWSConnector

import os
import json
import logging

try:
    client_config_file = os.environ["AGENT_CONFIG_FILE"]
except:
    client_config_file = "/etc/agent/Agent_config.tfvars.json"

with open(client_config_file, "r") as file:
    client_config_file = json.loads(file.read())


if __name__ == "__main__":
    ############################################################################
    # <1.> Create Grid Connector Library object
    ############################################################################

    logging.info("Simple Client")
    gridConnector = AWSConnector()

    ############################################################################
    # <2.> Authenticate with Amazon Cognito
    ############################################################################

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

    ############################################################################
    # <3.> Define two sample tasks to submit to the grid
    ############################################################################

    task_1_definition = {
        "worker_arguments": ["60000", "1", "1"]  # <--- This is task's payload that will
        # be serialized and submitted to the Data Plane
    }

    task_2_definition = {"worker_arguments": ["120000", "1", "1"]}

    ############################################################################
    # <4.> Submit all tasks in a single vector
    #      - Recevie back session ID to track  exectuion
    ############################################################################
    submission_resp = gridConnector.send([task_1_definition, task_2_definition])
    logging.info(submission_resp)

    ############################################################################
    # <5.> Use Session ID to wait until all tasks are completed
    ############################################################################
    results = gridConnector.get_results(submission_resp, timeout_sec=300)

    logging.info(results)
