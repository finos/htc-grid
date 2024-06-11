# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import json
import time
import os
import base64
import traceback

from botocore.exceptions import ClientError

from utils.performance_tracker import EventsCounter, performance_tracker_initializer
from api.state_table_manager import state_table_manager
from utils.state_table_common import (
    TASK_STATE_CANCELLED,
    TASK_STATE_FAILED,
    TASK_STATE_FINISHED,
)

import utils.grid_error_logger as errlog

state_table = state_table_manager(
    os.environ["STATE_TABLE_SERVICE"],
    os.environ["STATE_TABLE_CONFIG"],
    os.environ["STATE_TABLE_NAME"],
)

event_counter = EventsCounter(["invocations", "retrieved_rows"])

perf_tracker = performance_tracker_initializer(
    os.environ["METRICS_ARE_ENABLED"],
    os.environ["METRICS_GET_RESULTS_LAMBDA_CONNECTION_STRING"],
    os.environ["METRICS_GRAFANA_PRIVATE_IP"],
)


def get_time_now_ms():
    return int(round(time.time() * 1000))


def get_tasks_statuses_in_session(session_id):
    assert session_id is not None
    response = {
        "finished": [],
        "finished_OUTPUT": [],
        "cancelled": [],
        "cancelled_OUTPUT": [],
        "failed": [],
        "failed_OUTPUT": [],
    }

    # <1.> Process finished Tasks
    finished_tasks_resp = state_table.get_tasks_by_state(
        session_id, TASK_STATE_FINISHED
    )

    finished_tasks = finished_tasks_resp["Items"]
    if len(finished_tasks) > 0:
        response[TASK_STATE_FINISHED] = [x["task_id"] for x in finished_tasks]
        response[TASK_STATE_FINISHED + "_OUTPUT"] = [
            "read_from_dataplane" for x in finished_tasks
        ]

    # <2.> Process cancelled Tasks
    cancelled_tasks_resp = state_table.get_tasks_by_state(
        session_id, TASK_STATE_CANCELLED
    )

    cancelled_tasks = cancelled_tasks_resp["Items"]
    if len(cancelled_tasks) > 0:
        response[TASK_STATE_CANCELLED] = [x["task_id"] for x in cancelled_tasks]
        response[TASK_STATE_CANCELLED + "_OUTPUT"] = [
            "read_from_dataplane" for x in cancelled_tasks
        ]

    # <3.> Process failed Tasks
    failed_tasks_resp = state_table.get_tasks_by_state(session_id, TASK_STATE_FAILED)

    failed_tasks = failed_tasks_resp["Items"]
    if len(failed_tasks) > 0:
        response[TASK_STATE_FAILED] = [x["task_id"] for x in failed_tasks]
        response[TASK_STATE_FAILED + "_OUTPUT"] = [
            "read_from_dataplane" for x in failed_tasks
        ]

    # <4.> Process metadata
    response["metadata"] = {
        "tasks_in_response": len(finished_tasks)
        + len(cancelled_tasks)
        + len(failed_tasks)
    }

    return response


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

        return event["session_id"]

    else:
        errlog.log("Uniplemented path, exiting")
        assert False


def book_keeping(response):
    """
    Send relevant measurements
    """

    event_counter.increment("invocations")
    stats_obj = {
        "stage5_getres_01_invocation_tstmp": {
            "label": "None",
            "tstmp": get_time_now_ms(),
        }
    }

    event_counter.increment("retrieved_rows", response["metadata"]["tasks_in_response"])

    stats_obj["stage5_getres_02_invocation_over_tstmp"] = {
        "label": "get_results_invocation_time",
        "tstmp": get_time_now_ms(),
    }
    perf_tracker.add_metric_sample(
        stats_obj,
        event_counter=event_counter,
        from_event="stage5_getres_01_invocation_tstmp",
        to_event="stage5_getres_02_invocation_over_tstmp",
    )
    perf_tracker.submit_measurements()


def lambda_handler(event, context):
    session_id = None

    try:
        session_id = get_session_id_from_event(event)

        lambda_responce = get_tasks_statuses_in_session(session_id)

        book_keeping(lambda_responce)

        return {"statusCode": 200, "body": json.dumps(lambda_responce)}

    except ClientError as e:
        errlog.log(
            "Lambda get_result error: {} trace: {}".format(
                e.response["Error"]["Message"], traceback.format_exc()
            )
        )
        return {"statusCode": 542, "body": e.response["Error"]["Message"]}
    except Exception as e:
        errlog.log(
            "Lambda get_result error: {} trace: {}".format(e, traceback.format_exc())
        )
        return {"statusCode": 542, "body": "{}".format(e)}
