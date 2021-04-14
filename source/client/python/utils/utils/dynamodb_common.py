# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import logging
import random

from botocore.exceptions import ClientError
from boto3.dynamodb.conditions import Key

TASK_STATUS_CANCELLED = "cancelled"
TASK_STATUS_PENDING = "pending"
TASK_STATUS_FAILED = "failed"
TASK_STATUS_FINISHED = "finished"
TASK_STATUS_PROCESSING = "processing"
TASK_STATUS_RETRYING = "retrying"
TASK_STATUS_INCONSISTENT = "inconsistent"

DDB_TRANSACTION_MAX_SIZE = 25

N_LOGICAL_PARTITIONS_4_STATE = 32


def generate_random_logical_partition_name():
    return generate_logical_partition_name(None)


def generate_logical_partition_name(index=None):
    if index is not None:
        return "part{}".format(str(index).zfill(3))
    else:
        return generate_logical_partition_name(random.randint(0, N_LOGICAL_PARTITIONS_4_STATE - 1))


def state_partitions_generator():
    count = 0
    starting_state_id = random.randint(0, N_LOGICAL_PARTITIONS_4_STATE - 1)
    while count < N_LOGICAL_PARTITIONS_4_STATE:
        yield generate_logical_partition_name(starting_state_id % N_LOGICAL_PARTITIONS_4_STATE)
        count += 1
        starting_state_id += 1


def make_partition_key_4_state(task_state, session_id):
    res = "{}-{}".format(task_state, session_id[-7:])
    logging.info("PARTITION: {}".format(res))
    return "{}-{}".format(task_state, session_id[-7:])


def claim_task_to_yourself(status_table, task, self_id, expiration_timestamp):
    """ Alter table status_table where TaskId == wu.getTaskId()
        set Ownder = SelfWorkerID and status = Running and
        condition to status == Pending and OwnerID == None """
    logging.info("A2-claim_task_to_yourself -- 44 ")
    res = None
    try:
        res = status_table.update_item(
            Key={
                'task_id': task['task_id']
            },
            UpdateExpression="SET #var_task_owner = :val1, #var_task_status = :val2, #var_heartbeat_expiration_timestamp = :val3, #var_sqs_handler_id = :val4",
            ExpressionAttributeValues={
                ':val1': self_id,
                ':val2': make_partition_key_4_state('processing', task['session_id']),
                ':val3': expiration_timestamp,
                ':val4': task["sqs_handle_id"]

            },
            ExpressionAttributeNames={
                "#var_task_owner": "task_owner",
                "#var_task_status": "task_status",
                "#var_heartbeat_expiration_timestamp": "heartbeat_expiration_timestamp",
                "#var_sqs_handler_id": "sqs_handler_id"

            },
            ConditionExpression=Key('task_status').eq(
                make_partition_key_4_state('pending', task['session_id'])
            ) & Key('task_owner').eq('None'),
            ReturnConsumedCapacity="TOTAL"

        )

    except ClientError as e:

        if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
            logging.warning(
                "Could not acquire task [{}] from DynamoDB, someone else already locked it? {}".format(task['task_id'],
                                                                                                       e))
            return False, res, e
        elif e.response['Error']['Code'] in ["ThrottlingException", "ProvisionedThroughputExceededException"]:
            logging.warning(
                "Could not acquire task [{}] from DynamoDB, Throttling Exception {}".format(task['task_id'], e))
            return False, res, e
        else:
            logging.error(
                "Could not acquire task [{}] from DynamoDB: {}".format(task['task_id'], e))
            raise e
    except Exception as e:
        logging.error(
            "Could not acquire task [{}]: from DynamoDB: {}".format(e, task['task_id']))
        raise e

    return True, res, None


def update_own_tasks_ttl(status_table, task, self_id, expiration_timestamp):
    """ Alter table status_table where TaskId == wu.getTaskId()
        set HeartbeatExpirationTimestamp = expiration_timestamp
        condition to status == Running and OwnerID == SelfWorkerID """
    res = None
    try:
        res = status_table.update_item(
            Key={
                'task_id': task['task_id']
            },
            UpdateExpression="SET #var_heartbeat_expiration_timestamp = :val3",
            ExpressionAttributeValues={
                ':val3': expiration_timestamp,
            },
            ExpressionAttributeNames={
                "#var_heartbeat_expiration_timestamp": "heartbeat_expiration_timestamp",
            },
            ConditionExpression=Key('task_status').eq(
                make_partition_key_4_state('processing', task['session_id'])
            ) & Key('task_owner').eq(self_id)
        )

    except ClientError as e:

        if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
            logging.warning(
                "Could not update TTL on the own task [{}], did TTL Lambda re-assigned it? {}".format(task['task_id'], e))
            return False, res, e
        elif e.response['Error']['Code'] in ["ThrottlingException", "ProvisionedThroughputExceededException"]:
            logging.warning(
                "Could not update TTL on the own task [{}], Throttling Exception {}".format(task['task_id'], e))
            return False, res, e
        else:
            logging.error(
                "Could not update TTL on the own task [{}]: {}".format(task['task_id'], e))
            raise e

    except Exception as e:
        logging.error(
            "Could not update TTL on the own task [{}]: {}".format(e, task['task_id']))
        raise e

    return True, res, None


def dynamodb_update_task_status_to_finished(status_table, task, self_id):
    res = None
    try:
        res = status_table.update_item(
            Key={
                'task_id': task['task_id']
            },
            UpdateExpression="SET #var_task_status = :val1",
            ExpressionAttributeValues={
                ':val1': make_partition_key_4_state('finished', task['session_id'])
            },
            ExpressionAttributeNames={
                "#var_task_status": "task_status"
            },
            ConditionExpression=Key('task_status').eq(
                make_partition_key_4_state('processing', task['session_id'])
            ) & Key('task_owner').eq(self_id),
            ReturnConsumedCapacity="TOTAL"
        )

    except ClientError as e:

        if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
            logging.warning(
                "Could not set completion time to Finish on task: [{}], did TTL Lambda reassigned it? {}".format(task['task_id'], e))
            return False, res, e
        elif e.response['Error']['Code'] in ["ThrottlingException", "ProvisionedThroughputExceededException"]:
            logging.warning(
                "Could not set completion time to Finish on task: [{}], Throttling Exception {}".format(task['task_id'], e))
            return False, res, e

        else:
            logging.error(
                "Could not set completion time to Finish on task: [{}]: {}".format(task['task_id'], e))
            raise e

    except Exception as e:
        logging.error(
            "Could not set completion time to Finish on task: [{}]: {}".format(e, task['task_id']))
        raise e

    return True, res, None


def dynamodb_update_task_status_to_cancelled(status_table, session_id, task_id):
    res = None
    try:
        res = status_table.update_item(
            Key={
                'task_id': task_id
            },
            UpdateExpression="SET #var_task_status = :val1",
            ExpressionAttributeValues={
                ':val1': make_partition_key_4_state(TASK_STATUS_CANCELLED, session_id)
            },
            ExpressionAttributeNames={
                "#var_task_status": "task_status"
            },
            ReturnConsumedCapacity="TOTAL"
        )

    except ClientError as e:

        if e.response['Error']['Code'] in ["ThrottlingException", "ProvisionedThroughputExceededException"]:
            logging.warning(
                "Could not set completion time to Cancelled on task: [{}], Throttling Exception {}".format(task_id, e))
            return res

        else:
            logging.error(
                "Could not set completion time to Cancelled on task: [{}]: {}".format(task_id, e))
            raise e

    except Exception as e:
        logging.error(
            "Could not set completion time to Cancelled on task: [{}]: {}".format(e, task_id))
        raise e

    return res


def read_task_row(status_table, task_id, consistent_read=True):
    """
    Returns:
        An entire (raw) row from DynamoDB by task_id
    """
    response = None
    try:
        response = status_table.query(
            KeyConditionExpression=Key('task_id').eq(task_id),
            Select='ALL_ATTRIBUTES',
            ConsistentRead=consistent_read
        )

    except ClientError as e:

        if e.response['Error']['Code'] in ["ThrottlingException", "ProvisionedThroughputExceededException"]:
            logging.warning("Could not read row for task [{}] from Status Table. Exception: {}".format(task_id, e))
            return None
        else:
            logging.error("Could not read row for task [{}] from Status Table. Exception: {}".format(task_id, e))
            raise e
    except Exception as e:
        logging.error("Could not read row for task [{}] from Status Table. Exception: {}".format(task_id, e))
        raise e

    return response


def read_tasks_by_status(status_table, session_id, task_status):
    """

    Returns:
        Returns a list of tasks in the specified status from the associated session
    """

    key_expression = Key('session_id').eq(session_id) & Key('task_status').eq(make_partition_key_4_state(task_status, session_id))

    return read_tasks_by_status_key_expression(status_table, session_id, key_expression)


def read_tasks_by_status_key_expression(status_table, session_id, key_expression):
    """

    Returns:
        Returns a list of tasks in the specified status from the associated session
    """
    combined_response = None
    try:

        query_kwargs = {
            'IndexName': "gsi_session_index",
            'KeyConditionExpression': key_expression
        }

        last_evaluated_key = None
        done = False
        while not done:

            if last_evaluated_key:
                query_kwargs['ExclusiveStartKey'] = last_evaluated_key

            response = status_table.query(**query_kwargs)

            last_evaluated_key = response.get('LastEvaluatedKey', None)

            done = last_evaluated_key is None

            if not combined_response:
                combined_response = response
            else:
                combined_response['Items'] += response['Items']

        return combined_response

    except ClientError as e:

        if e.response['Error']['Code'] in ["ThrottlingException", "ProvisionedThroughputExceededException"]:
            logging.warning("Could not read tasks for session status [{}] by key expression from Status Table. Exception: {}".format(session_id, e))
            return None
        else:
            logging.error("Could not read tasks for session status [{}] by key expression from Status Table. Exception: {}".format(session_id, e))
            raise e
    except Exception as e:
        logging.error("Could not read tasks for session status [{}] by key expression from Status Table. Exception: {}".format(session_id, e))
        raise e

    return response
