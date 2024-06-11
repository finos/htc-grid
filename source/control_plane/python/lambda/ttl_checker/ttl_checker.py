# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import logging
import boto3
import time
import os
from datetime import datetime, timedelta

from botocore.exceptions import ClientError

from utils.performance_tracker import EventsCounter, performance_tracker_initializer
from utils import grid_error_logger as errlog

from utils.state_table_common import (
    TASK_STATE_RETRYING,
    TASK_STATE_INCONSISTENT,
    TASK_STATE_FAILED,
    StateTableException,
)
from api.queue_manager import queue_manager

region = os.environ["REGION"]

perf_tracker = performance_tracker_initializer(
    os.environ["METRICS_ARE_ENABLED"],
    os.environ["METRICS_TTL_CHECKER_LAMBDA_CONNECTION_STRING"],
    os.environ["METRICS_GRAFANA_PRIVATE_IP"],
)


from api.state_table_manager import state_table_manager

state_table = state_table_manager(
    os.environ["STATE_TABLE_SERVICE"],
    os.environ["STATE_TABLE_CONFIG"],
    os.environ["STATE_TABLE_NAME"],
)

queue = queue_manager(
    task_queue_service=os.environ["TASK_QUEUE_SERVICE"],
    task_queue_config=os.environ["TASK_QUEUE_CONFIG"],
    tasks_queue_name=os.environ["TASKS_QUEUE_NAME"],
    region=region,
)

dlq = queue_manager(
    task_queue_service=os.environ["TASK_QUEUE_SERVICE"],
    task_queue_config=os.environ["TASK_QUEUE_CONFIG"],
    tasks_queue_name=os.environ["TASKS_QUEUE_DLQ_NAME"],
    region=region,
)

cw_client = boto3.client("cloudwatch")

TTL_LAMBDA_ID = "TTL_LAMBDA"
TTL_LAMBDA_TMP_STATE = TASK_STATE_RETRYING
TTL_LAMBDA_FAILED_STATE = TASK_STATE_FAILED
TTL_LAMBDA_INCONSISTENT_STATE = TASK_STATE_INCONSISTENT
MAX_RETRIES = 5
RETRIEVE_EXPIRED_TASKS_LIMIT = 200

STATE_TABLE_THROTTLING_LIMIT_FOR_MEASURED_PERIOD = 1000


# TODO: implement archival after 10 days in S3


def lambda_handler(event, context):
    """Handler called by AWS Lambda runtime

    Args:
      event(dict): a CloudWatch Event generated every minute
      context:

    Returns:

    """
    stats_obj = {
        "01_invocation_tstmp": {
            "label": "None",
            "tstmp": int(round(time.time() * 1000)),
        }
    }
    event_counter = EventsCounter(
        [
            "counter_expired_tasks",
            "counter_failed_tasks",
            "counter_retried_tasks",
            "counter_retried_tasks_vto_reset_fail" "counter_tasks_queue_size",
            "counter_skip_check_under_throttling",
        ]
    )

    # <1.> If State Table is throttling we are skipping TTL checks.
    if is_state_table_under_throttling():
        logging.warning(
            "State Table experiencing throttling, skipping TTL checking for this cycle"
        )
        event_counter.increment("counter_skip_check_under_throttling", 1)

    else:
        for expired_tasks in state_table.query_expired_tasks():
            event_counter.increment("counter_expired_tasks", len(expired_tasks))
            event_counter.increment(
                "counter_tasks_queue_size", queue.get_queue_length()
            )

            for item in expired_tasks:
                print("Processing expired task: {}".format(item))
                task_id = item.get("task_id")
                owner_id = item.get("task_owner")

                # retreive current number of retries and task message handler
                (
                    retries,
                    task_sqs_handler_id,
                    task_priority,
                ) = retreive_retries_and_task_handler_and_priority(task_id)
                print(
                    f"Number of retires for task[{task_id}]: {retries} Priority: {task_priority}"
                )
                print(f"Last owner for task [{task_id}]: {owner_id}")

                if retries == MAX_RETRIES:
                    # TODO: MAX_RETRIES should be extracted from task definition... Store in DDB?
                    print(f"Failing task {task_id} after {retries} retries")
                    event_counter.increment("counter_failed_tasks")
                    fail_task(task_id, task_sqs_handler_id, task_priority)
                    continue

                if do_retry_task(task_id, retries + 1):
                    event_counter.increment("counter_retried_tasks")

                    try:
                        reset_task_msg_vto(task_sqs_handler_id, task_priority)
                        print("SUCCESS FIX for {}".format(task_id))

                    except ClientError as e:
                        print(e.response)
                        event_counter.increment("counter_retried_tasks_vto_reset_fail")
                        logging.warning(
                            "Could not reset VTO on a task that is being retried, continue..."
                        )

                    except Exception as e:
                        errlog.log(
                            f"TTL Lambda unexpected error during VTO reset: [{task_id}] [{e}]"
                        )
                        raise e

    stats_obj["02_completion_tstmp"] = {
        "label": "ttl_execution_time",
        "tstmp": int(round(time.time() * 1000)),
    }
    perf_tracker.add_metric_sample(
        stats_obj,
        event_counter=event_counter,
        from_event="01_invocation_tstmp",
        to_event="02_completion_tstmp",
    )
    perf_tracker.submit_measurements()


def is_state_table_under_throttling():
    """This function checks DynamoDB metrics in cloud watch to detect throttling events

    Returns:
      True if number of UpdateItem throttling events above defined threshold

    """

    response = cw_client.get_metric_statistics(
        Namespace="AWS/DynamoDB",
        MetricName="ThrottledRequests",
        Dimensions=[
            {"Name": "TableName", "Value": "htc_tasks_state_table-ddbtest"},
            {"Name": "Operation", "Value": "UpdateItem"},
        ],
        StartTime=datetime.utcnow() - timedelta(seconds=(1 * 60)),
        EndTime=datetime.utcnow(),
        Period=60,
        Statistics=["Sum"],
        Unit="Count",
    )

    throttling_events = 0
    for datapoint in response["Datapoints"]:
        throttling_events += datapoint["Sum"]
    print(
        f"Throttling events observed : {throttling_events} \
      allowed limit: {STATE_TABLE_THROTTLING_LIMIT_FOR_MEASURED_PERIOD}"
    )

    return throttling_events > STATE_TABLE_THROTTLING_LIMIT_FOR_MEASURED_PERIOD


def do_retry_task(task_id, new_retry_count):
    """This function attempts to re-try a task in the State Table.

    The most common way to not being able to perform the re-try is when the task has been
    already completed by the worker. There is always a raice condition here. Occurs more often when
    state table is throttling.

    Returns:
      True/False on success or failure

    """
    try:
        state_table.retry_task(task_id, new_retry_count)
        return True

    except StateTableException as e:
        if e.caused_by_condition:
            logging.warning(
                f"TTL Checker can not reset task [{task_id}] due to condition error. \
        Perhaps task has been finished by the worker. Skipping task"
            )
            return False
        elif e.caused_by_throttling:
            logging.warning(
                f"TTL Checker can not claim Task [{task_id}] due to DynamoDB throtling. \
        Skipping task"
            )
            return False
    except Exception as e:
        errlog.log(
            f"Unexpected error in retrying task [{task_id}] by TTL Checker. Raising exception {e}"
        )
        raise e


def fail_task(task_id, task_sqs_handler_id, task_priority):
    """This function set the task_status of task to fail

    Args:
      task_id(str): the id of the task to update
      task_sqs_handler_id(str): the task handler associated to this task
      task_priority(int): the priority of the task.

    Returns:
      Nothing

    Raises:
      ClientError: if DynamoDB table cannot be updated

    """
    try:
        delete_message_from_queue(task_sqs_handler_id, task_priority)

        state_table.update_task_status_to_failed(task_id)

    except ClientError as e:
        errlog.log("Cannot fail task {} : {}".format(task_id, e))
        raise e


def delete_message_from_queue(task_sqs_handler_id, task_priority):
    """This function delete the message from the task queue

    Args:
      task_sqs_handler_id(str): the task handler associated of the message to be deleted
      task_priority(int): priority of the task

    Returns:
      Nothing

    Raises:
      ClientError: if task queue cannot be updated

    """

    try:
        queue.delete_message(task_sqs_handler_id, task_priority)
    except ClientError as e:
        errlog.log("Cannot delete message {} : {}".format(task_sqs_handler_id, e))
        raise e


def retreive_retries_and_task_handler_and_priority(task_id):
    """This function retrieve (i) the number of retries,
    (ii) the task's handler associated to an expired task
    and (iii) and the priority under which this task was executed.

    Args:
      task_id(str): the id of the expired task

    Returns:
      rtype: 3 variables

    Raises:
      ClientError: if DynamoDB query failed

    """

    try:
        resp_task = state_table.get_task_by_id(task_id)

        return (
            resp_task.get("retries"),
            resp_task.get("sqs_handler_id"),
            resp_task.get("task_priority"),
        )

    except ClientError as e:
        errlog.log(
            "Cannot retreive retries and handler for task {} : {}".format(task_id, e)
        )
        raise e


def reset_task_msg_vto(handler_id, task_priority):
    """Function makes message re-appear in the tasks queue.

    Args:
      handler_id: reference of the message/task.
      task_priority: priority of the task. Identifies which queue to use (if applicable)

    Returns: Nothing

    """
    try:
        visibility_timeout_sec = 0
        queue.change_visibility(handler_id, visibility_timeout_sec, task_priority)

    except ClientError as e:
        errlog.log("Cannot reset VTO for message {} : {}".format(handler_id, e))
        raise e


def send_to_dlq(item):
    """

    Args:
      task:

    Returns:

    """
    logging.warning(f"Sending task [{item}] to DLQ")

    messages = [{"Id": item.get("task_id"), "MessageBody": str(item)}]

    dlq.send_messages(message_bodies=messages)
