# Copyright 2024 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


import boto3
import sys
import time
import os
import json

try:
    agent_config_file = os.environ["AGENT_CONFIG_FILE"]
except KeyError:
    agent_config_file = "/etc/agent/Agent_config.tfvars.json"

try:
    with open(agent_config_file, "r") as file:
        agent_config_data = json.loads(file.read())
except OSError:
    # This path is expected to be executed in Lambdas which don't have config
    # files
    agent_config_data = {
        "error_log_group": os.environ["ERROR_LOG_GROUP"],
        "error_logging_stream": os.environ["ERROR_LOGGING_STREAM"],
        "region": os.environ["REGION"],
    }


cw = boto3.client("logs", agent_config_data["region"])


# DEBUGGING
def log(
    message,
    log_group_name=agent_config_data["error_log_group"],
    log_stream_name=agent_config_data["error_logging_stream"],
):
    # print("ERROR-PRINT: {}".format(message))

    try:
        # retreive seq number
        response = cw.describe_log_streams(logGroupName=log_group_name)
        seq = None
        logEvents = [{"timestamp": int(time.time() * 1000), "message": message}]
        for lg in response.get("logStreams"):
            if lg.get("logStreamName") == log_stream_name:
                seq = lg.get("uploadSequenceToken")
        if seq is None:
            response = cw.put_log_events(
                logGroupName=log_group_name,
                logStreamName=log_stream_name,
                logEvents=logEvents,
            )
        else:
            response = cw.put_log_events(
                logGroupName=log_group_name,
                logStreamName=log_stream_name,
                logEvents=logEvents,
                sequenceToken=seq,
            )
    except Exception as e:
        print("Cannot log errors because {}".format(e), file=sys.stderr)
