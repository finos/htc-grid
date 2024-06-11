# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import json

import boto3
import base64
import os
import traceback

import utils.grid_error_logger as errlog

from utils.state_table_common import (
    TASK_STATE_PENDING,
    TASK_STATE_PROCESSING,
    StateTableException,
)

client = boto3.client("dynamodb")
dynamodb = boto3.resource("dynamodb")

from api.state_table_manager import state_table_manager

state_table = state_table_manager(
    os.environ["STATE_TABLE_SERVICE"],
    os.environ["STATE_TABLE_CONFIG"],
    os.environ["STATE_TABLE_NAME"],
)

task_states_to_cancel = [TASK_STATE_PENDING, TASK_STATE_PROCESSING]


def cancel_tasks_by_status(session_id, task_state):
    """
    Cancel tasks of in the specific state within a session.

    Args:
        string: session_id
        string: task_state

    Returns:
        dict: results

    """

    response = state_table.get_tasks_by_state(session_id, task_state)
    print(f"state_table.get_tasks_by_state: {response}")

    try:
        for row in response["Items"]:
            state_table.update_task_status_to_cancelled(row["task_id"])

    except StateTableException as e:
        errlog.log(
            "StateTableException error in setting task's status to cancelled {} [{}]".format(
                e, traceback.format_exc()
            )
        )
        raise e
    except Exception as e:
        errlog.log(
            "Unexpected error in in setting task's status to cancelled {} [{}]".format(
                e, traceback.format_exc()
            )
        )
        raise e

    return response["Items"]


def cancel_session(session_id):
    """
    Cancel all tasks within a session

    Args:
        string: session_id

    Returns:
        dict: results

    """

    lambda_response = {}

    all_cancelled_tasks = []
    for state in task_states_to_cancel:
        res = cancel_tasks_by_status(session_id, state)
        print(
            "Cancelling session: {} status: {} result: {}".format(
                session_id, state, res
            )
        )

        lambda_response["cancelled_{}".format(state)] = len(res)

        all_cancelled_tasks += res

    lambda_response["total_cancelled_tasks"] = len(all_cancelled_tasks)

    return lambda_response


def get_session_id_from_event(event):
    """
    Args:
        lambda's invocation event

    Returns:
        str: session id encoded in the event
    """

    # If lambda are called through ALB - extracting actual event
    if event.get("queryStringParameters") is not None:
        all_params = event.get("queryStringParameters")
        encoded_json_tasks = all_params.get("submission_content")
        if encoded_json_tasks is None:
            raise Exception(
                "Invalid submission format, expect submission_content parameter"
            )
        decoded_json_tasks = base64.urlsafe_b64decode(encoded_json_tasks).decode(
            "utf-8"
        )
        event = json.loads(decoded_json_tasks)

        return event["session_ids_to_cancel"]

    else:
        errlog.log("Unimplemented path, exiting")
        assert False


def lambda_handler(event, context):
    try:
        lambda_response = {}

        session_ids_to_cancel = get_session_id_from_event(event)

        for session2cancel in session_ids_to_cancel:
            lambda_sub_response = cancel_session(session2cancel)

            lambda_response[session2cancel] = lambda_sub_response

        return {"statusCode": 200, "body": json.dumps(lambda_response)}

    except Exception as e:
        errlog.log(
            "Lambda cancel_tasks error: {} trace: {}".format(e, traceback.format_exc())
        )
        return {"statusCode": 542, "body": "{}".format(e)}
