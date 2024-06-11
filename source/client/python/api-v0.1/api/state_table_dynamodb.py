# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError
from boto3.dynamodb.conditions import Key, Attr

import time
import logging
import json
import hashlib
import random
import traceback


from utils.state_table_common import (
    TASK_STATE_CANCELLED,
    TASK_STATE_PENDING,
    TASK_STATE_FAILED,
    TASK_STATE_PROCESSING,
    TASK_STATE_FINISHED,
)
from utils.state_table_common import StateTableException


logging.basicConfig(
    format="%(asctime)s - %(levelname)s - %(filename)s - %(funcName)s  - %(lineno)d - %(message)s",
    datefmt="%H:%M:%S",
    level=logging.INFO,
)


class StateTableDDB:
    def __init__(self, state_table_config, tasks_state_table_name, region=None):
        self.config = json.loads(state_table_config)

        if "retries" in self.config:
            ddb_config = None

            ddb_config = Config(retries=self.config["retries"])

            self.dynamodb_resource = boto3.resource(
                "dynamodb", region_name=region, config=ddb_config
            )

        else:
            self.dynamodb_resource = boto3.resource("dynamodb")

        self.state_table = self.dynamodb_resource.Table(tasks_state_table_name)

        # max N. rows per batch write/flush.
        self.MAX_WRITE_BATCHS_SIZE = 500

        # max failed tasks to process per call.
        self.RETRIEVE_EXPIRED_TASKS_LIMIT = 200

        self.MAX_STATE_PARTITIONS = 32

    # ---------------------------------------------------------------------------------------------
    # Common Methods ------------------------------------------------------------------------------
    # ---------------------------------------------------------------------------------------------
    def batch_write(self, entries=[]):
        """
        Function writes batch of rows into DynamoDB table
        Args:
            entries - rows to write into table
        Returns:
            Nothing

        Throws:
            StateTableException - on throttling
            Exception - for any other unexpected exception
        """

        tasks_batches = [
            entries[x: x + self.MAX_WRITE_BATCHS_SIZE]
            for x in range(0, len(entries), self.MAX_WRITE_BATCHS_SIZE)
        ]
        for ddb_batch in tasks_batches:
            with self.state_table.batch_writer() as batch:  # batch_writer is flushed when exiting this block
                for entry in ddb_batch:
                    try:
                        batch.put_item(Item=entry)

                    except ClientError as e:
                        if e.response["Error"]["Code"] in [
                            "ThrottlingException",
                            "ProvisionedThroughputExceededException",
                        ]:
                            msg = f"DynamoDB Batch Write Failed from DynamoDB, Throttling Exception [{e}] [{traceback.format_exc()}]"
                            logging.warning(msg)
                            raise StateTableException(e, msg, caused_by_throttling=True)

                        else:
                            msg = f"DynamoDB Batch Write Failed from DynamoDB Exception [{e}] [{traceback.format_exc()}]"
                            logging.error(msg)
                            raise Exception(e)

                    except Exception as e:
                        msg = f"DynamoDB Batch Write Failed from DynamoDB Exception [{e}] [{traceback.format_exc()}]"
                        logging.error(msg)
                        raise Exception(e)

    def get_task_by_id(self, task_id, consistent_read=False):
        """
        Args:
            task_id - string
        Returns:
            Dictionary containing a single task (dynamodb row)
            An entire (raw) row from DynamoDB by task_id
        """

        try:
            response = self.state_table.query(
                KeyConditionExpression=Key("task_id").eq(task_id),
                Select="ALL_ATTRIBUTES",
                ConsistentRead=consistent_read,
            )

            if (response is not None) and (len(response["Items"]) == 1):
                return response.get("Items")[0]
            else:
                return None

        except ClientError as e:
            if e.response["Error"]["Code"] in [
                "ThrottlingException",
                "ProvisionedThroughputExceededException",
            ]:
                logging.warning(
                    f"Could not read row for task [{task_id}] from Status Table. Exception: {e} [{traceback.format_exc()}]"
                )
                return None

            else:
                logging.error(
                    f"Could not read row for task [{task_id}] from Status Table. Exception: {e} [{traceback.format_exc()}]"
                )
                raise Exception(e)

        except Exception as e:
            logging.error(
                f"Could not read row for task [{task_id}] from Status Table. Exception: {e} [{traceback.format_exc()}]"
            )
            raise e

    # ---------------------------------------------------------------------------------------------
    # Methods used by TTL Lambda ------------------------------------------------------------------
    # ---------------------------------------------------------------------------------------------

    def update_task_status_to_failed(self, task_id):
        self.__finalize_tasks_state(task_id, TASK_STATE_FAILED)

    def update_task_status_to_cancelled(self, task_id):
        self.__finalize_tasks_state(task_id, TASK_STATE_CANCELLED)

    def query_expired_tasks(self):
        """
        Generator.
        For each call, returns a list of timed out tasks for a particular state partition, until run out of MAX_STATE_PARTITIONS to check
        """
        count = 0
        starting_state_id = random.randint(0, self.MAX_STATE_PARTITIONS - 1)
        while count < self.MAX_STATE_PARTITIONS:
            partition_to_check = self.__get_state_partition_at_index(
                starting_state_id % self.MAX_STATE_PARTITIONS
            )

            yield self.__get_expired_tasks_for_partition(partition_to_check)

            count += 1
            starting_state_id += 1

    def __get_expired_tasks_for_partition(self, state_partition):
        try:
            now = int(time.time())
            response = self.state_table.query(
                IndexName="gsi_ttl_index",
                KeyConditionExpression=Key("task_status").eq(
                    self.__make_task_state_from_state_and_partition(
                        TASK_STATE_PROCESSING, state_partition
                    )
                )
                & Key("heartbeat_expiration_timestamp").lt(now),
                Limit=self.RETRIEVE_EXPIRED_TASKS_LIMIT,
            )

            print(
                "Partition: {} expired tasks: {}".format(
                    state_partition, response["Items"]
                )
            )

            return response["Items"]

        except ClientError as e:
            if e.response["Error"]["Code"] in [
                "ThrottlingException",
                "ProvisionedThroughputExceededException",
            ]:
                msg = f"{__name__} Failed. Throttling."
                logging.warning(msg)
                raise StateTableException(e, msg, caused_by_throttling=True)

            else:
                msg = f"{__name__} Failed. Exception: [{e.response['Error']}]"
                logging.error(msg)
                raise Exception(e)

        except Exception as e:
            msg = f"{__name__} Failed. Exception: [{e.response['Error']}]"
            logging.error(msg)
            raise e

    def retry_task(self, task_id, new_retry_count):
        """
        Puts task back into pending state, available for workers to be picked up.
        Args:
            task_id: task id to be retired
            new_retry_count:
        Condition: task state should be in processing state still.

        Returns:
            Nothing
        """
        try:
            self.state_table.update_item(
                Key={"task_id": task_id},
                UpdateExpression="SET #var_task_owner = :val1, #var_task_status = :val2, #var_retries = :val3",
                ExpressionAttributeValues={
                    ":val1": "None",
                    ":val2": self.__make_task_state_from_task_id(
                        TASK_STATE_PENDING, task_id
                    ),
                    ":val3": new_retry_count,
                },
                ExpressionAttributeNames={
                    "#var_task_owner": "task_owner",
                    "#var_task_status": "task_status",
                    "#var_retries": "retries",
                },
                ConditionExpression=Attr("task_status").eq(
                    self.__make_task_state_from_task_id(TASK_STATE_PROCESSING, task_id)
                ),
                # & Attr('task_owner').eq(current_owner)
                # & Attr('heartbeat_expiration_timestamp').eq(current_heartbeat_timestamp)
            )

        except ClientError as e:
            if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
                msg = f"{__name__} Failed ConditionalCheckFailedException.\
                    task_id [{task_id}] is no longer in State: task_status [{self.__make_task_state_from_task_id(TASK_STATE_PROCESSING, task_id)}]\
                    [{e.response['Error']}]"
                logging.warning(msg)
                raise StateTableException(e, msg, caused_by_condition=True)

            if e.response["Error"]["Code"] in [
                "ThrottlingException",
                "ProvisionedThroughputExceededException",
            ]:
                msg = f"{__name__} Failed. Throttling."
                logging.warning(msg)
                raise StateTableException(e, msg, caused_by_throttling=True)

            else:
                msg = f"{__name__} Failed. Exception: [{e.response['Error']}]"
                logging.error(msg)
                raise Exception(e)

        except Exception as e:
            msg = f"{__name__} Failed. Exception: [{e.response['Error']}]"
            logging.error(msg)
            raise e

    # ---------------------------------------------------------------------------------------------
    # Methods used by Agent -----------------------------------------------------------------------
    # ---------------------------------------------------------------------------------------------

    def claim_task_for_agent(
        self, task_id, queue_handle_id, agent_id, expiration_timestamp
    ):
        """
        Once task has been consumed from the task queue, we need to update the owner and the state of the task in the state table.

        Approximately equivalent to SQL:
        Alter table state_table where TaskId == task_id
        set Ownder = SelfWorkerID and task_status = Running and
        condition to status == Pending and OwnerID == None

        Args:
            task_id: picked task
            queue_handle_id: handle to manipulate visibility timeout at a later stage
            agent_id: i.e., the worker ID that is working on this task
            expiration_timestamp: heartbeat for TTL

        Returns:
            True if claim succesfull

        Throws:
            StateTableException on throttling
            StateTableException on condition
            Exception for all other errors
        """

        session_id = self.__get_session_id_from_task_id(task_id)

        claim_is_successful = True

        try:
            self.state_table.update_item(
                Key={"task_id": task_id},
                UpdateExpression="SET #var_task_owner = :val1, #var_task_status = :val2, #var_heartbeat_expiration_timestamp = :val3, #var_sqs_handler_id = :val4",
                ExpressionAttributeValues={
                    ":val1": agent_id,
                    ":val2": self.__make_task_state_from_session_id(
                        TASK_STATE_PROCESSING, session_id
                    ),
                    ":val3": expiration_timestamp,
                    ":val4": queue_handle_id,
                },
                ExpressionAttributeNames={
                    "#var_task_owner": "task_owner",
                    "#var_task_status": "task_status",
                    "#var_heartbeat_expiration_timestamp": "heartbeat_expiration_timestamp",
                    "#var_sqs_handler_id": "sqs_handler_id",
                },
                ConditionExpression=Key("task_status").eq(
                    self.__make_task_state_from_session_id(
                        TASK_STATE_PENDING, session_id
                    )
                )
                & Key("task_owner").eq("None"),
            )

        except ClientError as e:
            if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
                msg = f"Could not acquire task [{task_id}] for status [{self.__make_task_state_from_session_id(TASK_STATE_PENDING, session_id)}] from DynamoDB, someone else already locked it? [{e}]"
                logging.warning(msg)
                raise StateTableException(e, msg, caused_by_condition=True)

            elif e.response["Error"]["Code"] in [
                "ThrottlingException",
                "ProvisionedThroughputExceededException",
            ]:
                msg = f"Could not acquire task [{task_id}] from DynamoDB, Throttling Exception {e}"
                logging.warning(msg)
                raise StateTableException(e, msg, caused_by_throttling=True)

            else:
                msg = f"ClientError while acquire task [{task_id}] from DynamoDB: {e}"
                logging.error(msg)
                raise Exception(e)

        except Exception as e:
            msg = f"Failed to acquire task [{task_id}] for agent [{agent_id}]: from DynamoDB: {e}"
            logging.error(msg)
            raise e

        return claim_is_successful

    def refresh_ttl_for_ongoing_task(self, task_id, agent_id, new_expirtaion_timestamp):
        """
        Function updates TTL for the task

        Approximately equivalent to SQL:
        Alter table state_table where TaskId == wu.getTaskId()
        set HeartbeatExpirationTimestamp = expiration_timestamp
        condition to status == Running and OwnerID == SelfWorkerID

        Args:
            task_id: the task to update
            agent_id: expected worker id that is working on this task.
            new_expirtaion_timestamp: a timestamp in the "future" when this task will be considered expired.

        Returns:
            True if successful

        Throws:
            StateTableException on throttling
            StateTableException on condition
            Exception for all other errors
        """

        session_id = self.__get_session_id_from_task_id(task_id)

        refresh_is_successful = True
        try:
            self.state_table.update_item(
                Key={"task_id": task_id},
                UpdateExpression="SET #var_heartbeat_expiration_timestamp = :val3",
                ExpressionAttributeValues={
                    ":val3": new_expirtaion_timestamp,
                },
                ExpressionAttributeNames={
                    "#var_heartbeat_expiration_timestamp": "heartbeat_expiration_timestamp",
                },
                ConditionExpression=Key("task_status").eq(
                    self.__make_task_state_from_session_id(
                        TASK_STATE_PROCESSING, session_id
                    )
                )
                & Key("task_owner").eq(agent_id),
            )

        except ClientError as e:
            if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
                task_row = self.get_task_by_id(task_id, consistent_read=True)
                msg = f"Could not update TTL on the own task [{task_id}] agent: [{agent_id}] state: [{self.__make_task_state_from_session_id(TASK_STATE_PROCESSING, session_id)}], did TTL Lambda re-assigned it? TaskRow: [{task_row}] {e}"
                logging.warning(msg)
                raise StateTableException(e, msg, caused_by_condition=True)

            elif e.response["Error"]["Code"] in [
                "ThrottlingException",
                "ProvisionedThroughputExceededException",
            ]:
                msg = f"Could not update TTL on the own task [{task_id}] agent: [{agent_id}], Throttling Exception {e}"
                logging.warning(msg)
                raise StateTableException(e, msg, caused_by_throttling=True)

            else:
                msg = f"Could not update TTL on the own task [{task_id}] agent: [{agent_id}]: {e}"
                logging.error(msg)
                raise Exception(e)

        except Exception as e:
            msg = f"Could not update TTL on the own task [{task_id}]: {e}"
            logging.error(msg)
            raise e

        return refresh_is_successful

    def update_task_status_to_finished(self, task_id, agent_id):
        """
        Attempts to move task into finished state.

        Args:
            task_id: task to be updated
            agent_id: expected worker id

        Returns:
            True if successful

        Throws:
            StateTableException on throttling
            StateTableException on condition
            Exception for all other errors
        """

        session_id = self.__get_session_id_from_task_id(task_id)

        update_succesfull = True

        try:
            self.state_table.update_item(
                Key={"task_id": task_id},
                UpdateExpression="SET #var_task_status = :val1, #var_task_completion_timestamp = :val2",
                ExpressionAttributeValues={
                    ":val1": self.__make_task_state_from_session_id(
                        TASK_STATE_FINISHED, session_id
                    ),
                    ":val2": int(round(time.time() * 1000)),
                },
                ExpressionAttributeNames={
                    "#var_task_status": "task_status",
                    "#var_task_completion_timestamp": "task_completion_timestamp",
                },
                ConditionExpression=Key("task_status").eq(
                    self.__make_task_state_from_session_id(
                        TASK_STATE_PROCESSING, session_id
                    )
                )
                & Key("task_owner").eq(agent_id),
            )

        except ClientError as e:
            if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
                #  For debugging purposes we re-read the row to later identify why exactly condition has failed.
                check_read = self.get_task_by_id(task_id, consistent_read=True)

                msg = f"Could not set completion state to Finish. ConditionalCheckFailedException\
                    on task:  [{task_id}] owner [{agent_id}] for status [{self.__make_task_state_from_session_id(TASK_STATE_PENDING, session_id)}] from DynamoDB,\
                    someone else already locked it? [{e}]. Check State Table read: [{check_read}]"

                logging.warning(msg)
                raise StateTableException(e, msg, caused_by_condition=True)

            elif e.response["Error"]["Code"] in [
                "ThrottlingException",
                "ProvisionedThroughputExceededException",
            ]:
                msg = f"Could not set completion state to Finish on task:  [{task_id}] from DynamoDB, Throttling Exception {e}"
                logging.warning(msg)
                raise StateTableException(e, msg, caused_by_throttling=True)

            else:
                msg = f"Could not set completion state to Finish on task: [{task_id}] from DynamoDB: {e}"
                logging.error(msg)
                raise Exception(e)

        except Exception as e:
            msg = f"Could not set completion state to Finish on task: [{task_id}] for agent [{agent_id}]: from DynamoDB: {e}"
            logging.error(msg)
            raise e

        return update_succesfull

    # ---------------------------------------------------------------------------------------------
    # Methods used by Submit Tasks Lambda ---------------------------------------------------------
    # ---------------------------------------------------------------------------------------------
    def make_task_state_from_session_id(self, task_state, session_id):
        return self.__make_task_state_from_session_id(task_state, session_id)

    def get_tasks_by_state(self, session_id, task_status):
        """
        Returns:
            Returns a list of tasks in the specified status from the associated session
        """

        key_expression = Key("session_id").eq(session_id) & Key("task_status").eq(
            self.__make_task_state_from_session_id(task_status, session_id)
        )

        return self.__get_tasks_by_state_key_expression(session_id, key_expression)

    def __get_tasks_by_state_key_expression(self, session_id, key_expression):
        """
        Returns:
            Returns a list of tasks in the specified status from the associated session

        Throws:
            StateTableException on throttling
            Exception for all other errors

        """

        combined_response = None
        try:
            query_kwargs = {
                "IndexName": "gsi_session_index",
                "KeyConditionExpression": key_expression,
            }

            last_evaluated_key = None
            done = False
            while not done:
                if last_evaluated_key:
                    query_kwargs["ExclusiveStartKey"] = last_evaluated_key

                response = self.state_table.query(**query_kwargs)

                last_evaluated_key = response.get("LastEvaluatedKey", None)

                done = last_evaluated_key is None

                if not combined_response:
                    combined_response = response
                else:
                    combined_response["Items"] += response["Items"]

            return combined_response

        except ClientError as e:
            if e.response["Error"]["Code"] in [
                "ThrottlingException",
                "ProvisionedThroughputExceededException",
            ]:
                msg = f"Could not read tasks for session status [{session_id}] by key expression from Status Table. Exception: {e}"
                logging.warning(msg)
                raise StateTableException(e, msg, caused_by_throttling=True)

            else:
                msg = f"Could not read tasks for session status [{session_id}] by key expression from Status Table. Exception: {e}"
                logging.warning(msg)
                raise Exception(e)

        except Exception as e:
            logging.error(
                "Could not read tasks for session status [{}] by key expression from Status Table. Exception: {}".format(
                    session_id, e
                )
            )
            raise e

    # ---------------------------------------------------------------------------------------------
    #  Private Methods ----------------------------------------------------------------------------
    # ---------------------------------------------------------------------------------------------

    def __get_state_partition_from_task_id(self, task_id):
        return self.__get_state_partition_from_session_id(
            self.__get_session_id_from_task_id(task_id)
        )

    def __get_session_id_from_task_id(self, task_id):
        return task_id.split("_")[0]

    def __get_state_partition_from_session_id(self, session_id):
        r = self.__get_state_partition_at_index(
            int(hashlib.md5(session_id.encode()).hexdigest(), 16)
        )
        return r

    def __get_state_partition_at_index(self, index):
        return index % self.MAX_STATE_PARTITIONS

    def __make_task_state_from_task_id(self, task_state, task_id):
        return self.__make_task_state_from_session_id(
            task_state, self.__get_session_id_from_task_id(task_id)
        )

    def __make_task_state_from_session_id(self, task_state, session_id):
        res = self.__make_task_state_from_state_and_partition(
            task_state, self.__get_state_partition_from_session_id(session_id)
        )

        return res

    def __make_task_state_from_state_and_partition(self, task_state, partition_id):
        res = "{}{}".format(task_state, partition_id)
        logging.info("PARTITION: {}".format(res))

        return res

    def __finalize_tasks_state(self, task_id, new_task_state):
        """
        This function called to move tasks into its final states.
        This function does not check the conditions and simply overwrites old state with the new.

        Args:
            task_id: task to move into new final state
            new_task_state: the new final state

        Returns:
            Nothing

        Throws:
            StateTableException on throttling
            Exception for all other errors
        """
        if new_task_state not in [TASK_STATE_FAILED, TASK_STATE_CANCELLED]:
            logging.error(
                "__finalize_tasks_state called with incorrect input: {}".format(
                    new_task_state
                )
            )

        try:
            self.state_table.update_item(
                Key={"task_id": task_id},
                UpdateExpression="SET #var_task_owner = :val1, #var_task_status = :val2",
                ExpressionAttributeValues={
                    ":val1": "None",
                    ":val2": self.__make_task_state_from_task_id(
                        new_task_state, task_id
                    ),
                },
                ExpressionAttributeNames={
                    "#var_task_owner": "task_owner",
                    "#var_task_status": "task_status",
                },
            )

        except ClientError as e:
            if e.response["Error"]["Code"] in [
                "ThrottlingException",
                "ProvisionedThroughputExceededException",
            ]:
                msg = f"{__name__} Failed. Throttling. task_id [{task_id}] new state [{new_task_state}] {traceback.format_exc()}"
                logging.warning(msg)
                raise StateTableException(e, msg, caused_by_throttling=True)

            else:
                msg = f"{__name__} Failed. task_id [{task_id}] new state [{new_task_state}]\
                    Exception: [{e.response['Error']}] {traceback.format_exc()}"
                logging.error(msg)
                raise Exception(e)

        except Exception as e:
            msg = f"{__name__} Failed. task_id [{task_id}] new state [{new_task_state}]\
                Exception: [{e}] {traceback.format_exc()}"
            logging.error(msg)
            raise e
