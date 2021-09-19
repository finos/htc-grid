# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

from api.connector import HTCGridConnector
from api.session import GridSession

import time
import os
import json
import logging

try:
    client_config_file = os.environ['AGENT_CONFIG_FILE']
except:
    client_config_file = "/etc/agent/Agent_config.tfvars.json"

with open(client_config_file, 'r') as file:
    client_config_file = json.loads(file.read())


TOTAL_COUNT = 0
# Sample function callback
def sample_callback(worker_lambda_response):
    global TOTAL_COUNT
    TOTAL_COUNT += 1
    print(f"{TOTAL_COUNT}\tOK: {worker_lambda_response}")

    # do some computation

    pass

if __name__ == "__main__":

    logging.info("Simple Client V2")
    try:
        username = os.environ['USERNAME']
    except KeyError:
        username = ""
    try:
        password = os.environ['PASSWORD']
    except KeyError:
        password = ""


    # <1.> Establishes connection to one of many available HTC-Grids
    grid_connector = HTCGridConnector(client_config_file, username=username, password=password)

    # <2.> Authentication based on the configuration file above
    grid_connector.authenticate()


    # <3.> Create session object with corresponding context & callback
    context = {
        "session_priority" : 1
    }

    grid_session = grid_connector.create_session(
        service_name="MyService1",
        context=context,
        callback=sample_callback)


    grid_session_2 = grid_connector.create_session(
        service_name="MyService1",
        context=context,
        callback=sample_callback)


    # <4.> Submit tasks for the session
    task_1_definition = {
        "worker_arguments": ["1000", "1", "1"]
    }

    task_2_definition = {
        "worker_arguments": ["2000", "1", "1"]
    }

    grid_session.send([task_1_definition, task_2_definition])

    grid_session_2.send([task_1_definition, task_2_definition])

    # <5.> Submit additional tasks within the same session
    time.sleep(1)
    grid_session.send([task_1_definition, task_2_definition])

    grid_session_2.send([task_1_definition, task_2_definition])


    # Blocking wait for completion
    grid_session.wait_for_completion(timeout_ms=3000)

    print(grid_session.submitted_task_ids)

    print(grid_session.received_task_ids)

    grid_session.wait_for_completion()
    grid_session_2.wait_for_completion()

    # grid_session.cancel()

    # Close session
    grid_session.close()
    grid_session_2.close()

    # Close connector and stop thread
    grid_connector.close(wait_for_sessions_completion=True)

