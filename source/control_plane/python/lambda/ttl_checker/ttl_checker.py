# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import boto3
import time
import os

from botocore.exceptions import ClientError
from boto3.dynamodb.conditions import Key, Attr

from utils.performance_tracker import EventsCounter, performance_tracker_initializer
from utils import grid_error_logger as errlog

from utils.dynamodb_common import state_partitions_generator, TASK_STATUS_RETRYING, TASK_STATUS_INCONSISTENT, TASK_STATUS_FAILED

region = os.environ["REGION"]

perf_tracker = performance_tracker_initializer(
    os.environ["METRICS_ARE_ENABLED"],
    os.environ["METRICS_TTL_CHECKER_LAMBDA_CONNECTION_STRING"],
    os.environ["METRICS_GRAFANA_PRIVATE_IP"])


dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TASKS_STATUS_TABLE_NAME'])
sqs_res = boto3.resource('sqs', region_name=region, endpoint_url=f'https://sqs.{region}.amazonaws.com')
sqs_cli = boto3.client('sqs', endpoint_url=f'https://sqs.{region}.amazonaws.com')
queue = sqs_res.get_queue_by_name(QueueName=os.environ['TASKS_QUEUE_NAME'])
dlq = sqs_res.get_queue_by_name(QueueName=os.environ['TASKS_QUEUE_DLQ_NAME'])

TTL_LAMBDA_ID = 'TTL_LAMBDA'
TTL_LAMBDA_TMP_STATUS = TASK_STATUS_RETRYING
TTL_LAMBDA_FAILED_STATUS = TASK_STATUS_FAILED
TTL_LAMBDA_INCONSISTENT_STATUS = TASK_STATUS_INCONSISTENT
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

    # We start with a random partition and iterate through all 10
    # pindex = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u',
    #           'v', 'w', 'x', 'y', 'z',
    #           'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U',
    #           'V', 'W', 'X', 'Y', 'Z']
    # ddb_partition = random.randint(0, len(pindex) - 1)
    # for offset in range(0, len(pindex)):
    #     ddb_part_str = "-" + pindex[(ddb_partition + offset) % len(pindex)]

    for partition_name in state_partitions_generator():
        ddb_part_str = "-" + partition_name

        expired_tasks = retreive_expired_tasks(ddb_part_str)
        event_counter.increment("counter_expired_tasks", len(expired_tasks['Items']))
        event_counter.increment("counter_tasks_queue_size",
                                int(queue.attributes.get('ApproximateNumberOfMessages')))

        print("Partition: {} expired tasks: {}".format(ddb_part_str, expired_tasks['Items']))

        for item in expired_tasks.get('Items'):
            task_id = item.get('task_id')
            owner_id = item.get('task_owner')
            current_heartbeat_timestamp = item.get('heartbeat_expiration_timestamp')
            try:
                is_acquired = acquire_task(task_id, owner_id, current_heartbeat_timestamp, ddb_part_str)

                if not is_acquired:
                    # task has been updated at the very last second...
                    event_counter.increment("counter_failed_to_acquire")
                    continue

                # retreive current number of retries and SQS_handler
                retries, sqs_handler_id = retreive_retries_and_sqs_handler(task_id)
                print("Number of retires for task[{}]: {}".format(task_id, retries))
                print("Last owner for task [{}]: {}".format(task_id, owner_id))

                # TODO: MAX_RETRIES should be extracted from task definition... Store in DDB?
                if retries == MAX_RETRIES:
                    print("Failing task {} after {} retries".format(task_id, retries))
                    event_counter.increment("counter_failed_tasks")
                    fail_task(task_id, sqs_handler_id, ddb_part_str)
                    continue

                event_counter.increment("counter_released_tasks")
                # else
                release_task(task_id, retries + 1, ddb_part_str)

                try:
                    # Task can be acquired by an agent from this point
                    reset_sqs_vto(sqs_handler_id)
                    print("SUCCESS FIX for {}".format(task_id))

                except ClientError:

                    try:
                        errlog.log('Failed to reset VTO trying to delete: {} '.format(task_id))
                        delete_message_from_queue(sqs_handler_id)
                    except ClientError:
                        errlog.log('Inconsistent task: {} sending do DLQ'.format(task_id))
                        event_counter.increment("counter_inconsistent_state")
                        set_task_inconsistent(task_id, ddb_part_str)
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


def fail_task(task_id, sqs_handler_id, ddb_part_str):
    """This function set the task_status of task to fail

    Args:
      task_id(str): the id of the task to update
      sqs_handler_id(str): the sqs handler associated to this task
      ddb_part_str(str): DynamoDB info to forward to the status

    Returns:
      Nothing

    Raises:
      ClientError: if DynamoDB table cannot be updated

    """
    try:
        delete_message_from_queue(sqs_handler_id)
        table.update_item(
            Key={
                'task_id': task_id
            },
            UpdateExpression="SET #var_task_owner = :val1, #var_task_status = :val2",
            ExpressionAttributeValues={
                ':val1': 'None',
                ':val2': TTL_LAMBDA_FAILED_STATUS + ddb_part_str
            },
            ExpressionAttributeNames={
                "#var_task_owner": "task_owner",
                "#var_task_status": "task_status"
            }
        )
    except ClientError as e:
        errlog.log("Cannot fail task {} : {}".format(task_id, e))
        raise e


def set_task_inconsistent(task_id, ddb_part_str):
    """This function set the task_status of task to inconsistent

    Args:
      task_id(str): the id of the task to update
      ddb_part_str(str): DynamoDB info to forward to the status

    Returns:
      Nothing

    Raises:
      ClientError: if DynamoDB table cannot be updated

    """
    try:
        table.update_item(
            Key={
                'task_id': task_id
            },
            UpdateExpression="SET #var_task_owner = :val1, #var_task_status = :val2",
            ExpressionAttributeValues={
                ':val1': 'None',
                ':val2': TTL_LAMBDA_INCONSISTENT_STATUS + ddb_part_str
            },
            ExpressionAttributeNames={
                "#var_task_owner": "task_owner",
                "#var_task_status": "task_status"
            },
            # This condition is probably redundant and should be removed in the future
            ConditionExpression=Key('task_owner').eq('None')
        )
    except ClientError as e:
        errlog.log("Cannot set task to inconsystent {} : {}".format(task_id, e))
        raise e


def delete_message_from_queue(sqs_handler_id):
    """This function delete a message from a SQS queue

    Args:
      sqs_handler_id(str): the sqs handler associated of the message to be deleted

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


def retreive_expired_tasks(ddb_part_str):
    """This function retrieves the list of expired tasks from the DynamoDB table

    Args:
      ddb_part_str(str): DynamoDB infO

    Returns:
      dict: a list of expired tasks

    Raises:
      ClientError: if DynamoDB query failed

    """
    try:
        now = int(time.time())
        response = table.query(
            IndexName="gsi_ttl_index",
            KeyConditionExpression=Key('task_status').eq('processing' + ddb_part_str)
                                   & Key('heartbeat_expiration_timestamp').lt(now),
            Limit=RETRIEVE_EXPIRED_TASKS_LIMIT
        )
        return response
    except ClientError as e:
        errlog.log("Cannot retreive expired tasks : {}".format(e))
        raise e


def retreive_retries_and_sqs_handler(task_id):
    """This function retrieve the number of retries and the SQS handler associated to an expired task

    Args:
      task_id(str): the id of the expired task

    Returns:
      rtype: dict

    Raises:
      ClientError: if DynamoDB query failed

    """
    try:
        response = table.query(
            KeyConditionExpression=Key('task_id').eq(task_id)
        )
        # CHeck if 1 and only 1
        return response.get('Items')[0].get('retries'), response.get('Items')[0].get('sqs_handler_id')
    except ClientError as e:
        errlog.log("Cannot retreive retries and handler for task {} : {}".format(task_id, e))
        raise e


def release_task(task_id, retries, ddb_part_str):
    """

    Args:
      task_id:
      retries:
      ddb_part_str:

    Returns:

    """
    try:
        table.update_item(
            Key={
                'task_id': task_id
            },
            UpdateExpression="SET #var_task_owner = :val1, #var_task_status = :val2, #var_retries = :val3",
            ExpressionAttributeValues={
                ':val1': 'None',
                ':val2': 'pending' + ddb_part_str,
                ':val3': retries
            },
            ExpressionAttributeNames={
                "#var_task_owner": "task_owner",
                "#var_task_status": "task_status",
                "#var_retries": "retries"
            }
        )
    except ClientError as e:
        errlog.log("Cannot release task {} : {}".format(task_id, e))
        raise e


def reset_sqs_vto(handler_id):
    """

    Args:
      handler_id:

    Returns:

    """
    try:
        sqs_cli.change_message_visibility(
            QueueUrl=queue.url,
            ReceiptHandle=handler_id,
            VisibilityTimeout=0
        )
    except ClientError as e:
        errlog.log("Cannot reset VTO for message {} : {}".format(handler_id, e))
        raise e


def acquire_task(task_id, current_owner, current_heartbeat_timestamp, ddb_part_str):
    """

    Args:
      task_id:
      current_owner:
      current_heartbeat_timestamp:
      ddb_part_str:

    Returns:

    """
    try:
        table.update_item(
            Key={
                'task_id': task_id
            },
            UpdateExpression="SET #var_task_owner = :val1, #var_task_status = :val2, #var_hb_timestamp = :val3",
            ExpressionAttributeValues={
                ':val1': TTL_LAMBDA_ID,
                ':val2': TTL_LAMBDA_TMP_STATUS + ddb_part_str,
                ':val3': 0
            },
            ExpressionAttributeNames={
                "#var_task_owner": "task_owner",
                "#var_task_status": "task_status",
                "#var_hb_timestamp": "heartbeat_expiration_timestamp"
            },
            ConditionExpression=Attr('task_status').eq('processing' + ddb_part_str)
                                & Attr('task_owner').eq(current_owner)
                                & Attr('heartbeat_expiration_timestamp').eq(current_heartbeat_timestamp)
        )
    except ClientError as e:
        errlog.log("Cannot acquire task TTL Checker {} : {}".format(task_id, e))
        return False
    return True


def send_to_dlq(task):
    """

    Args:
      task:

    Returns:

    """
    print("Sending task [{}] to DLQ".format(task))
    dlq.send_message(MessageBody=str(task))
