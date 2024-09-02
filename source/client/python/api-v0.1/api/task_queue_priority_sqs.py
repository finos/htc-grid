# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


import logging
import json
import traceback

from api.task_queue_sqs import QueueSQS
from utils.task_queue_common import TaskQueueException
from utils import grid_error_logger as errlog

logging.basicConfig(
    format="%(asctime)s - %(levelname)s - %(filename)s - %(funcName)s  - %(lineno)d - %(message)s",
    datefmt="%H:%M:%S",
    level=logging.INFO,
)


class QueuePrioritySQS:
    def __init__(self, endpoint_url, task_queue_config, first_queue_name, region):
        """
        QueuePrioritySQS implemented using multiple SQS queues. This class is a wrapper
        around a list of QueueSQS with an additional logic to keep mapping between
        message handle id and a queue from which this message was received.
        """

        self.endpoint_url = endpoint_url
        self.config = json.loads(task_queue_config)
        self.priorities_count = self.config["priorities"]

        self.msg_handle_to_queue_lookup = {}
        self.priority_to_queue_lookup = {}

        self.priorities = [x for x in range(0, self.priorities_count)]

        for priority in self.priorities:
            # Expected format htc_task_queue-<TAG>__<QUEUE PRIORITY>
            # e.g., htc_task_queue-kbgcncl__1
            queue_name = first_queue_name.split("__")[0] + "__{}".format(priority)

            self.priority_to_queue_lookup[priority] = QueueSQS(
                endpoint_url, queue_name, region
            )

    def send_messages(self, message_bodies=[], message_attributes={}):
        """
        Sends a single message or a batch of messages into SQS queue

        Args:
            message_bodies - list of messages to be send
            message_attributes - dictionary that should contain priority

        Returns:
            response from SQS

        """

        try:
            if "priority" in message_attributes:
                queue = self.priority_to_queue_lookup[message_attributes["priority"]]
            else:
                queue = self.priority_to_queue_lookup[0]

            response = queue.send_messages(message_bodies, message_attributes)

        except Exception as e:
            msg = f"Priority QueueSQS: failed to send {len(message_bodies)} messages [{message_bodies}], Exception: [{e}] [{traceback.format_exc()}]"
            errlog.log(msg)
            raise TaskQueueException(e, msg, traceback.format_exc())

        return response

    def receive_message(self, wait_time_sec=0) -> dict:
        """
        # Receives a message from the front of the task queue based on p
        Iterates over list of QueueSQS based on priorities and attempts to receive a message
        from the from of each. The first successfully received message is returned.

        Args:
            wait_time_sec - pulling time out. NOTE: By default priority queue emulation
            with multi SQS does not perform long polling as it need to iterate over several queues.
            Performing long polling on each queue would significantly increase latency.


        Returns:
            empty dictionary if no mesage was read from the queue, otherwise
            a dictionary containing the body of the message + associated properties

        """
        wait_time_sec = 0

        for priority in reversed(self.priorities):
            queue = self.priority_to_queue_lookup[priority]

            queue_sqs_response = queue.receive_message(wait_time_sec)

            if "body" in queue_sqs_response:
                self.msg_handle_to_queue_lookup[
                    queue_sqs_response["properties"]["message_handle_id"]
                ] = queue

                return queue_sqs_response

        return {}

    def delete_message(self, message_handle_id, task_priority=None):
        """Deletes message from the queue by the message_handle_id or task_priority
        Often this function is called when message is successfully consumed.

        Args:
            message_handle_id(str): the sqs handler associated of the message to be deleted
            task_priority(int):

        Returns: None
        """

        try:
            queue = self.__get_queue_object(message_handle_id, task_priority)

            res = queue.delete_message(message_handle_id)

            return res

        except Exception as e:
            msg = f"PrioritySQS: Failed to delete msg by handle_id [{message_handle_id}] priority [{task_priority}] : [{e}] [{traceback.format_exc()}]"
            errlog.log(msg)
            raise TaskQueueException(e, msg, traceback.format_exc())

    def change_visibility(
        self, message_handle_id, visibility_timeout_sec, task_priority=None
    ):
        """Changes visibility timeout of the message by its handle

        Args:
        message_handle_id(str): the sqs handler associated of the message to be deleted
        task_priority(int):

        Returns: None

        """

        try:
            queue = self.__get_queue_object(message_handle_id, task_priority)

            res = queue.change_visibility(message_handle_id, visibility_timeout_sec)

            return res

        except Exception as e:
            msg = f"PrioritySQS: Failed to change visibility by message_handle_id [{message_handle_id}] priority [{task_priority}] : [{e}] [{traceback.format_exc()}]"
            errlog.log(msg)
            raise TaskQueueException(e, msg, traceback.format_exc())

    def get_queue_length(self):
        """
        Returns total number of queued tasks across all queues under all priorities.

        """

        all_queued_tasks = sum(
            self.priority_to_queue_lookup[p].get_queue_length() for p in self.priorities
        )

        return all_queued_tasks

    def __get_queue_object(self, message_handle_id, task_priority=None) -> QueueSQS:
        """This function finds a corresponding queue by message_handle_id or task_priority

        Args:
            message_handle_id(str): the sqs handler associated of the message to be deleted
            task_priority(int): priority of the task

        Returns:
            QueueSQS

        """
        queue = None

        if message_handle_id in self.msg_handle_to_queue_lookup:
            # <1.> If this object was used to submit the message then we should have
            # a mapping from the handle to the queue object that was used to in-queue this message
            queue = self.msg_handle_to_queue_lookup[message_handle_id]

        elif task_priority is not None:
            # <2.> The message was in-queued by some external object, (this can happen if submit_tasks lambda
            # inserted the message, but now ttl_lambda is modifying the state of that message)
            # thus we should determine the name of the queue by using the priority argument.
            queue = self.priority_to_queue_lookup[task_priority]

        else:
            msg = "PrioritySQS: Can not find QueueSQS by message_handle_id [{message_handle_id}] and priority [{task_priority}]"
            errlog.log(msg)
            raise TaskQueueException(None, msg, traceback.format_exc())

        return queue
