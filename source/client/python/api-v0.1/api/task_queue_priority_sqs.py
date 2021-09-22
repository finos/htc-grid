# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


# from botocore.exceptions import ClientError

from api.task_queue_sqs import QueueSQS

import logging
import json
from utils import grid_error_logger as errlog

logging.basicConfig(format="%(asctime)s - %(levelname)s - %(filename)s - %(funcName)s  - %(lineno)d - %(message)s",
                    datefmt='%H:%M:%S', level=logging.INFO)


class QueuePrioritySQS:

    def __init__(self, endpoint_url, task_queue_config, first_queue_name, region):
        # Connection + Authentication

        self.endpoint_url = endpoint_url
        self.config = json.loads(task_queue_config)

        self.priorities_count = self.config["priorities"]
        self.msg_handle_to_queue_lookup = {}

        self.priority_to_queue_lookup = {}

        self.priorities = [x for x in range(0, self.priorities_count)]

        for priority in self.priorities:
            queue_name = first_queue_name.split("__")[0] + "__{}".format(priority)

            self.priority_to_queue_lookup[priority] = QueueSQS(endpoint_url, queue_name, region)

    # Single write &  Batch write
    def send_messages(self, message_bodies=[], message_attributes={}):

        if "priority" in message_attributes:
            queue = self.priority_to_queue_lookup[message_attributes["priority"]]
        else:
            queue = self.priority_to_queue_lookup[0]

        response = queue.send_messages(message_bodies, message_attributes)

        return response

    def receive_message(self, wait_time_sec=0):
        # By default priority queues does not perform long polling as it need to
        # iterate over serveral queues.
        wait_time_sec = 0

        res = None

        for priority in reversed(self.priorities):

            queue = self.priority_to_queue_lookup[priority]

            res = queue.receive_message(wait_time_sec)

            if "body" in res:
                # we have succesfully received a message
                self.msg_handle_to_queue_lookup[res["properties"]["message_handle_id"]] = queue

                return res

        return res

    def __get_queue_object(self, message_handle_id, task_priority=None):
        """This function finds a corresponding queue by message_handle_id or task_priority

        Args:
        message_handle_id(str): the sqs handler associated of the message to be deleted
        task_priority(int): priority of the task

        Returns:
            QueueSQS

        Raises:
            Exception: if QueueSQS cannot be found

        """
        queue = None

        if message_handle_id in self.msg_handle_to_queue_lookup:
            # <1.> If this object was used to submit the message then we should have
            # a mapping from the handle to the queue object that was used to inqueue the message
            queue = self.msg_handle_to_queue_lookup[message_handle_id]

        elif task_priority is not None:
            # <2.> The message was inqueued by some external object, thus we should determine the
            # name of the queue by using the priority argument.
            queue = self.priority_to_queue_lookup[task_priority]

        else:
            raise Exception("Can not find message to be deleted from SQS message_handle_id [{}] priority [{}]".format(
                            message_handle_id, task_priority)
                            )
        return queue

    def delete_message(self, message_handle_id, task_priority=None):
        # TODO: error/exception handling

        try:

            queue = self.__get_queue_object(message_handle_id, task_priority)

            res = queue.delete_message(message_handle_id)

            return res

        except Exception as e:
            errlog.log("Cannot delete message_handle_id [{}] priority [{}] : {}".format(
                message_handle_id, task_priority, e))
            raise e

    def change_visibility(self, message_handle_id, visibility_timeout_sec, task_priority=None):
        """Changes visibility timeout of the message by its handle

        Args:
        message_handle_id(str): the sqs handler associated of the message to be deleted
        task_priority(int): <Interface argument, not used in this class>

        Returns: None

        Raises: ClientError: on failure
        """

        try:

            queue = self.__get_queue_object(message_handle_id, task_priority)

            res = queue.change_visibility(message_handle_id, visibility_timeout_sec)

            return res

        except Exception as e:
            errlog.log("Cannot delete message_handle_id [{}] priority [{}] : {}".format(
                message_handle_id, task_priority, e))
            raise e

    def get_queue_length(self):
        """

        Args:

        Returns: total number of queued tasks across all queues under all priorities.

        """

        all_queued_tasks = sum(
            self.priority_to_queue_lookup[p].get_queue_length()
            for p in self.priorities
        )

        return all_queued_tasks
