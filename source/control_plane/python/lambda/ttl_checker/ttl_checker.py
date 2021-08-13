# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import boto3
import time
import os

from botocore.exceptions import ClientError
from boto3.dynamodb.conditions import Key, Attr

from utils.performance_tracker import EventsCounter, performance_tracker_initializer
from utils.state_table_common import *
from utils import grid_error_logger as errlog

from utils.state_table_common import TASK_STATE_RETRYING, TASK_STATE_INCONSISTENT, TASK_STATE_FAILED

region = os.environ["REGION"]

perf_tracker = performance_tracker_initializer(
    os.environ["METRICS_ARE_ENABLED"],
    os.environ["METRICS_TTL_CHECKER_LAMBDA_CONNECTION_STRING"],
    os.environ["METRICS_GRAFANA_PRIVATE_IP"])


from api.state_table_manager import state_table_manager
state_table = state_table_manager(
    os.environ['STATE_TABLE_SERVICE'],
    os.environ['STATE_TABLE_CONFIG'],
    os.environ['STATE_TABLE_NAME'])

sqs_res = boto3.resource('sqs', region_name=region, endpoint_url=f'https://sqs.{region}.amazonaws.com')
sqs_cli = boto3.client('sqs', endpoint_url=f'https://sqs.{region}.amazonaws.com')
queue = sqs_res.get_queue_by_name(QueueName=os.environ['TASKS_QUEUE_NAME'])
dlq = sqs_res.get_queue_by_name(QueueName=os.environ['TASKS_QUEUE_DLQ_NAME'])

TTL_LAMBDA_ID = 'TTL_LAMBDA'
TTL_LAMBDA_TMP_STATE = TASK_STATE_RETRYING
TTL_LAMBDA_FAILED_STATE = TASK_STATE_FAILED
TTL_LAMBDA_INCONSISTENT_STATE = TASK_STATE_INCONSISTENT
MAX_RETRIES = 5
RETRIEVE_EXPIRED_TASKS_LIMIT = 200


# TODO: implement archival after 10 days in S3

def lambda_handler(event, context):
    """Handler called by AWS Lambda runtime

    Args:
      event(dict): a CloudWatch Event generated every minute
      context:

    Returns:

    """
    stats_obj = {'01_invocation_tstmp': {"label": "None", "tstmp": int(round(time.time() * 1000))}}
    event_counter = EventsCounter(
        ["counter_expired_tasks", "counter_failed_to_acquire",
         "counter_failed_tasks", "counter_released_tasks", "counter_inconsistent_state", "counter_tasks_queue_size"])

    for expired_tasks in state_table.query_expired_tasks():

        # expired_tasks = retreive_expired_tasks(ddb_part_str)
        event_counter.increment("counter_expired_tasks", len(expired_tasks))
        event_counter.increment("counter_tasks_queue_size",
                                int(queue.attributes.get('ApproximateNumberOfMessages')))

        for item in expired_tasks:
            print("Processing expired task: {}".format(item))
            task_id = item.get('task_id')
            owner_id = item.get('task_owner')
            current_heartbeat_timestamp = item.get('heartbeat_expiration_timestamp')
            try:
                is_acquired = state_table.acquire_task_for_ttl_lambda(
                    task_id, owner_id, current_heartbeat_timestamp)

                if not is_acquired:
                    # task has been updated at the very last second...
                    event_counter.increment("counter_failed_to_acquire")
                    continue

                # retreive current number of retries and SQS_handler
                retries, sqs_handler_id, task_priority = retreive_retries_and_sqs_handler_and_priority(task_id)
                print("Number of retires for task[{}]: {} Priority: {}".format(task_id, retries, task_priority))
                print("Last owner for task [{}]: {}".format(task_id, owner_id))

                # TODO: MAX_RETRIES should be extracted from task definition... Store in DDB?
                if retries == MAX_RETRIES:
                    print("Failing task {} after {} retries".format(task_id, retries))
                    event_counter.increment("counter_failed_tasks")
                    fail_task(task_id, sqs_handler_id, task_priority)
                    continue

                event_counter.increment("counter_released_tasks")
                # else
                state_table.retry_task(task_id, retries + 1)

                try:
                    # Task can be acquired by an agent from this point
                    reset_sqs_vto(sqs_handler_id, task_priority)
                    print("SUCCESS FIX for {}".format(task_id))

                except ClientError:

                    try:
                        errlog.log('Failed to reset VTO trying to delete: {} '.format(task_id))
                        delete_message_from_queue(sqs_handler_id)
                    except ClientError:
                        errlog.log('Inconsistent task: {} sending do DLQ'.format(task_id))
                        event_counter.increment("counter_inconsistent_state")
                        set_task_inconsistent(task_id)
                        send_to_dlq(item)

            except ClientError as e:
                errlog.log('Lambda ttl error: {}'.format(e.response['Error']['Message']))
                print("Cannot process task {} : {}".format(task_id, e))
                print("Sending task {} to DLQ...".format(task_id))
                send_to_dlq(item)
            except Exception as e:
                print("Cannot process task {} : {}".format(task_id, e))
                print("Sending task {} to DLQ...".format(task_id))
                errlog.log('Lambda ttl error: {}'.format(e))
                send_to_dlq(item)

    stats_obj['02_completion_tstmp'] = {"label": "ttl_execution_time", "tstmp": int(round(time.time() * 1000))}
    perf_tracker.add_metric_sample(
        stats_obj,
        event_counter=event_counter,
        from_event="01_invocation_tstmp",
        to_event="02_completion_tstmp"
    )
    perf_tracker.submit_measurements()


def fail_task(task_id, sqs_handler_id, task_priority):
    """This function set the task_status of task to fail

    Args:
      task_id(str): the id of the task to update
      sqs_handler_id(str): the sqs handler associated to this task
      task_priority(int): the priority of the task.

    Returns:
      Nothing

    Raises:
      ClientError: if DynamoDB table cannot be updated

    """
    try:
      delete_message_from_queue(sqs_handler_id, task_priority)

      state_table.update_task_status_to_failed(task_id)

    except ClientError as e:
      errlog.log("Cannot fail task {} : {}".format(task_id, e))
      raise e


def set_task_inconsistent(task_id):
    """This function set the task_status of task to inconsistent

    Args:
      task_id(str): the id of the task to update

    Returns:
      Nothing

    Raises:
      ClientError: if DynamoDB table cannot be updated

    """
    try:

        state_table.update_task_status_to_inconsistent(task_id)

    except ClientError as e:
        errlog.log("Cannot set task to inconsystent {} : {}".format(task_id, e))
        raise e


def delete_message_from_queue(sqs_handler_id, task_priority):
    """This function delete a message from a SQS queue

    Args:
      sqs_handler_id(str): the sqs handler associated of the message to be deleted
      task_priority(int): priority of the task

    Returns:
      Nothing

    Raises:
      ClientError: if SQS queue cannot be updated

    """

    try:
        sqs_cli.delete_message(
            QueueUrl=queue.url,
            ReceiptHandle=sqs_handler_id
        )
    except ClientError as e:
        errlog.log("Cannot delete message {} : {}".format(sqs_handler_id, e))
        raise e





def retreive_retries_and_sqs_handler_and_priority(task_id):
    """This function retrieve (i) the number of retries,
    (ii) the SQS handler associated to an expired task
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
        # CHeck if 1 and only 1
        return resp_task.get('retries'),\
               resp_task.get('sqs_handler_id'),\
               resp_task.get('task_priority')

    except ClientError as e:
        errlog.log("Cannot retreive retries and handler for task {} : {}".format(task_id, e))
        raise e


def reset_sqs_vto(handler_id, task_priority):
    """

    Args:
      handler_id:

    Returns:

    """
    try:
        visibility_timeout_sec = 0
        sqs_cli.change_message_visibility(
            QueueUrl=queue.url,
            ReceiptHandle=handler_id,
            VisibilityTimeout=0
        )

    except ClientError as e:
        errlog.log("Cannot reset VTO for message {} : {}".format(handler_id, e))
        raise e




def send_to_dlq(task):
    """

    Args:
      task:

    Returns:

    """
    print("Sending task [{}] to DLQ".format(task))
    dlq.send_message(MessageBody=str(task))
