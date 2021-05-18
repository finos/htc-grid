# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

from api.connector import AWSConnector

import os
import json
import logging

try:
    client_config_file = os.environ['AGENT_CONFIG_FILE']
except:
    client_config_file = "/etc/agent/Agent_config.tfvars.json"

with open(client_config_file, 'r') as file:
    client_config_file = json.loads(file.read())


if __name__ == "__main__":

    logging.info("Simple Client")
    gridConnector = AWSConnector()
    
    try:
        username = os.environ['USERNAME']
    except KeyError:
        username = ""
    try:
        password = os.environ['PASSWORD']
    except KeyError:
        password = ""

    gridConnector.init(client_config_file, username=username, password=password)    
    gridConnector.authenticate()

    task_1_definition = {
        "worker_arguments": ["1000", "1", "1"]
    }

    task_2_definition = {
        "worker_arguments": ["2000", "1", "1"]
    }

    submission_resp = gridConnector.send([task_1_definition, task_2_definition])
    logging.info(submission_resp)


    results = gridConnector.get_results(submission_resp, timeout_sec=100)
    logging.info(results)