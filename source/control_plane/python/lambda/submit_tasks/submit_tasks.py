# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import json
import base64
import boto3
import time
import os
import uuid
import traceback
import copy

from botocore.exceptions import ClientError

from utils.performance_tracker import EventsCounter, performance_tracker_initializer

from boto3.dynamodb.conditions import Key

import utils.grid_error_logger as errlog
from utils.state_table_common import TASK_STATE_PENDING

from api.in_out_manager import in_out_manager
from api.queue_manager import queue_manager
from api.state_table_manager import state_table_manager

region = os.environ["REGION"]

sqs = boto3.resource("sqs", endpoint_url=f"https://sqs.{region}.amazonaws.com")

tasks_queue = queue_manager(
    task_queue_service=os.environ["TASK_QUEUE_SERVICE"],
    task_queue_config=os.environ["TASK_QUEUE_CONFIG"],
    tasks_queue_name=os.environ["TASKS_QUEUE_NAME"],
    region=region,
)

state_table = state_table_manager(
    os.environ["STATE_TABLE_SERVICE"],
    os.environ["STATE_TABLE_CONFIG"],
    os.environ["STATE_TABLE_NAME"],
    os.environ["REGION"],
)

perf_tracker = performance_tracker_initializer(
    os.environ["METRICS_ARE_ENABLED"],
    os.environ["METRICS_SUBMIT_TASKS_LAMBDA_CONNECTION_STRING"],
    os.environ["METRICS_GRAFANA_PRIVATE_IP"],
)

task_input_passed_via_external_storage = os.environ[
    "TASK_INPUT_PASSED_VIA_EXTERNAL_STORAGE"
]
stdin_iom = in_out_manager(
    os.environ["GRID_STORAGE_SERVICE"],
    os.environ["S3_BUCKET"],
    os.environ["REDIS_URL"],
    os.environ["REDIS_PASSWORD"],
)


def write_to_dynamodb(task_json, batch):
    """

    Args:
      task_json:
      batch:

    Returns:

    """

    try:
        response = batch.put_item(Item=task_json)
    except Exception as e:
        print(e)
        raise

    return response


def write_to_sqs(sqs_batch_entries, session_priority=0):
    """
    Args:
      sqs_batch_entries: batch of tasks monikers to be submitted for scheduling

    Returns:

    """
    try:
        response = tasks_queue.send_messages(
            message_bodies=sqs_batch_entries,
            message_attributes={"priority": session_priority},
        )
        if response.get("Failed") is not None:
            # Should also send to DLQ
            raise Exception("Batch write to SQS failed - check DLQ")
    except Exception as e:
        print("{}".format(e))
        raise

    return response


def get_time_now_ms():
    """This method returns the current time in millisecond (ms)

    Args:

    Returns:
        int: the current  time in millisecond

    """
    return int(round(time.time() * 1000))


def verify_passed_sessionid_is_unique(session_id):
    """This function if a given session has already been used by DynamoDB

    Args:
      session_id(str): the session id to verify

    Returns:
      Nothing

    Raises:
      Exception:

    """
    response = table.query(
        IndexName="gsi_session_index",
        KeyConditionExpression=Key("session_id").eq(session_id),
    )

    if len(response["Items"]) > 0:
        raise Exception(
            "Passed session id [{}] already in DDB, uuid is not unique!".format(
                session_id
            )
        )


def lambda_handler(event, context):
    """Handler called by AWS Lambda runtime

    Args:
      event (dict): an dictionary object containing the HTTP status code and the message to send back to the client):
      an API Gateway generated event
      context:

    Returns:
        dict: A message and a status code bind in dictionary object


    """
    # If lambda are called through ALB - extracting actual event
    if event.get("queryStringParameters") is not None:
        all_params = event.get("queryStringParameters")
        if task_input_passed_via_external_storage == "1":
            session_id = all_params.get("submission_content")
            encoded_json_tasks = stdin_iom.get_payload_to_utf8_string(session_id)
        else:
            encoded_json_tasks = all_params.get("submission_content")
        if encoded_json_tasks is None:
            raise Exception(
                "Invalid submission format, expect submission_content parameter"
            )
        decoded_json_tasks = base64.urlsafe_b64decode(encoded_json_tasks).decode(
            "utf-8"
        )
        event = json.loads(decoded_json_tasks)
    else:
        encoded_json_tasks = event["body"]
        decoded_json_tasks = base64.urlsafe_b64decode(encoded_json_tasks).decode(
            "utf-8"
        )
        event = json.loads(decoded_json_tasks)

    try:
        invocation_tstmp = get_time_now_ms()

        print(event)

        # Session ID that will be used for all tasks in this event.
        if event["session_id"] == "None":
            # Generate new session id if no session is passed
            # TODO: We are not currently supporting this option, consider for removal and replace with assertion
            session_id = get_safe_session_id()
        else:
            session_id = event["session_id"]
            # verify_passed_sessionid_is_unique(session_id)
        session_priority = 0
        if "context" in event:
            session_priority = event["context"]["tasks_priority"]

        parent_session_id = event["session_id"]

        lambda_response = {"session_id": session_id, "task_ids": []}

        sqs_batch_entries = []
        last_submitted_task_ref = None

        tasks_list = event["tasks_list"]["tasks"]
        ddb_batch_write_times = []
        backoff_count = 0

        state_table_entries = []
        for task_id in tasks_list:
            time_now_ms = get_time_now_ms()
            task_definition = "none"

            task_json = {
                "session_id": session_id,
                "task_id": task_id,
                "parent_session_id": parent_session_id,
                "submission_timestamp": time_now_ms,
                "task_completion_timestamp": 0,
                "task_status": state_table.make_task_state_from_session_id(
                    TASK_STATE_PENDING, session_id
                ),
                "task_owner": "None",
                "retries": 0,
                "task_definition": task_definition,
                "sqs_handler_id": "None",
                "heartbeat_expiration_timestamp": 0,
                "task_priority": session_priority,
            }

            state_table_entries.append(task_json)

            task_json_4_sqs: dict = copy.deepcopy(task_json)

            task_json_4_sqs["stats"] = event["stats"]
            task_json_4_sqs["stats"]["stage2_sbmtlmba_01_invocation_tstmp"][
                "tstmp"
            ] = invocation_tstmp
            task_json_4_sqs["stats"]["stage2_sbmtlmba_02_before_batch_write_tstmp"][
                "tstmp"
            ] = get_time_now_ms()

            # task_json["scheduler_data"] = event["scheduler_data"]

            sqs_batch_entries.append(
                {
                    "Id": task_id,  # use to return send result for this message
                    "MessageBody": json.dumps(task_json_4_sqs),
                }
            )

            last_submitted_task_ref = task_json_4_sqs

        state_table.batch_write(state_table_entries)

        # <2.> Batch submit tasks to SQS
        # Performance critical code
        sqs_max_batch_size = 10
        sqs_batch_chunks = [
            sqs_batch_entries[x: x + sqs_max_batch_size]
            for x in range(0, len(sqs_batch_entries), sqs_max_batch_size)
        ]
        for chunk in sqs_batch_chunks:
            write_to_sqs(chunk, session_priority)

        # <3.> Non performance critical code, statistics and book-keeping.
        event_counter = EventsCounter(
            [
                "count_submitted_tasks",
                "count_ddb_batch_backoffs",
                "count_ddb_batch_write_max",
                "count_ddb_batch_write_min",
                "count_ddb_batch_write_avg",
            ]
        )
        event_counter.increment("count_submitted_tasks", len(sqs_batch_entries))

        last_submitted_task_ref["stats"]["stage2_sbmtlmba_03_invocation_over_tstmp"] = {
            "label": "dynamo_db_submit_ms",
            "tstmp": get_time_now_ms(),
        }

        event_counter.increment("count_ddb_batch_backoffs", backoff_count)

        if len(ddb_batch_write_times) > 0:
            event_counter.increment(
                "count_ddb_batch_write_max", max(ddb_batch_write_times)
            )
            event_counter.increment(
                "count_ddb_batch_write_min", min(ddb_batch_write_times)
            )
            event_counter.increment(
                "count_ddb_batch_write_avg",
                sum(ddb_batch_write_times) * 1.0 / len(ddb_batch_write_times),
            )

        print(
            "BKF: [{}] LEN: {} LIST: {}".format(
                backoff_count, len(ddb_batch_write_times), ddb_batch_write_times
            )
        )

        perf_tracker.add_metric_sample(
            last_submitted_task_ref["stats"],
            event_counter=event_counter,
            from_event="stage1_grid_api_01_task_creation_tstmp",
            to_event="stage2_sbmtlmba_03_invocation_over_tstmp",
            # event_time=(datetime.datetime.fromtimestamp(invocation_tstmp/1000.0)).isoformat()
        )
        perf_tracker.submit_measurements()

        # <4.> Asswmble the response
        for sqs_msg in sqs_batch_entries:
            lambda_response["task_ids"].append(sqs_msg["Id"])

        return {"statusCode": 200, "body": json.dumps(lambda_response)}
    except ClientError as e:
        errlog.log(
            "ClientError in Submit Tasks {} {}".format(
                e.response["Error"]["Code"], traceback.format_exc()
            )
        )

        return {"statusCode": 543, "body": e.response["Error"]["Message"]}

    except Exception as e:
        errlog.log(
            "Exception in Submit Tasks {} [{}]".format(e, traceback.format_exc())
        )

        return {"statusCode": 543, "body": "{}".format(e)}


# From 3.7, we can check if UUID is safe (i.e. unique even in case of mutliprocessing)
# it seems that the first call to uuid in Lambda environment can produces unsafe UUID.
# check if at least the second UUID provided is safe, otherwise errors out
def get_safe_session_id():
    """This method generates a safe session ID.

    Args:

    Returns:
      str: a safe session id

    Raises:
      Exception: if session id is not safe

    """
    session_id = uuid.uuid1()
    if session_id.is_safe != uuid.SafeUUID.safe:
        print("Need to create a second UUID")
        session_id = uuid.uuid1()
    if session_id.is_safe != uuid.SafeUUID.safe:
        raise Exception("Cannot produce a safe unique ID")

    return str(session_id)


def main():
    """This function execute the hanlder outside of the lambda environment

    Args:

    Returns:

    """
    event = {
        "scheduler_data": {"task_timeout_sec": 3600, "retry_count": 5},
        "tasks_list": {
            "tasks": [
                {
                    "command_line": "bin/FXloader.out",
                    "args": ["1", "2", "3"],
                    "stdin": "protobuf string",
                    "env_variables": {"var_name": "value"},
                },
                {
                    "command_line": "bin/FXloader.out",
                    "args": ["1", "2", "3"],
                    "stdin": "protobuf string",
                    "env_variables": {"var_name": "value"},
                },
                {
                    "command_line": "bin/FXloader.out",
                    "args": ["1", "2", "3"],
                    "stdin": "protobuf string",
                    "env_variables": {"var_name": "value"},
                },
            ]
        },
    }
    res = lambda_handler(event=event, context=None)
    print(res)


if __name__ == "__main__":
    # execute only if run as a script
    os.environ["TASKS_QUEUE_NAME"] = "sample_task_queue"
    os.environ["STATE_TABLE_CONFIG"] = "sample_tasks_state_table"
    os.environ["METRICS_ARE_ENABLED"] = "0"

    main()
