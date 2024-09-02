# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import boto3
import logging
import traceback

from utils.task_queue_common import TaskQueueException

from utils import grid_error_logger as errlog

logging.basicConfig(
    format="%(asctime)s - %(levelname)s - %(filename)s - %(funcName)s  - %(lineno)d - %(message)s",
    datefmt="%H:%M:%S",
    level=logging.INFO,
)


class QueueSQS:
    def __init__(self, endpoint_url, queue_name, region):
        logging.info(f"Initializing QueueSQS: {endpoint_url} {queue_name} {region}")

        self.endpoint_url = endpoint_url

        self.queue_name = queue_name

        try:
            sqs_resource = boto3.resource(
                "sqs", region_name=region, endpoint_url=endpoint_url
            )

            self.sqs_queue = sqs_resource.get_queue_by_name(QueueName=queue_name)

            self.sqs_client = boto3.client(
                "sqs", region_name=region, endpoint_url=endpoint_url
            )

        except Exception as e:
            msg = f"QueueSQS: cannot initialize queue_name [{queue_name}], endpoint_url [{endpoint_url}] region [{region}] : {e} [{traceback.format_exc()}]"
            errlog.log(msg)
            raise TaskQueueException(e, msg, traceback.format_exc())

    def send_messages(self, message_bodies=[], message_attributes={}):
        """
        Sends a single message or a batch of messages into SQS queue

        Args:
            message_bodies - list of messages to be send
            message_attributes - unused parameter for singe SQS task queue

        Returns:
            response from SQS

        """

        try:
            return self.sqs_queue.send_messages(Entries=message_bodies)

        except Exception as e:
            msg = f"QueueSQS: failed to send {len(message_bodies)} messages [{message_bodies}], Exception: [{e}] [{traceback.format_exc()}]"
            errlog.log(msg)
            raise TaskQueueException(e, msg, traceback.format_exc())

    def receive_message(self, wait_time_sec=10):
        """
        Receives a message from the front of the task queue

        Args:
            wait_time_sec - pulling time out


        Returns:
            empty dictionary if no mesage was read from the queue, otherwise
            a dictionary containing the body of the message + associated properties

        """

        messages = []
        try:
            messages = self.sqs_queue.receive_messages(
                MaxNumberOfMessages=1, WaitTimeSeconds=wait_time_sec
            )

        except Exception as e:
            msg = f"QueueSQS: failed to receive a task from SQS queue, Exception: [{e}] [{traceback.format_exc()}]"
            errlog.log(msg)
            raise TaskQueueException(e, msg, traceback.format_exc())

        if len(messages) == 0:
            return {}

        return {
            "body": messages[0].body,
            "properties": {"message_handle_id": messages[0].receipt_handle},
        }

    def delete_message(self, message_handle_id, task_priority=None) -> None:
        """Deletes message from the queue by the message_handle_id.
        Often this function is called when message is successfully consumed.

        Args:
            message_handle_id(str): the sqs handler associated of the message to be deleted
            task_priority(int): <Interface argument, not used in this class>

        Returns: None
        """

        try:
            self.sqs_client.delete_message(
                QueueUrl=self.sqs_queue.url, ReceiptHandle=message_handle_id
            )

        except Exception as e:
            msg = f"QueueSQS: Cannot delete message by handle id {message_handle_id}, Exception: [{e}] [{traceback.format_exc()}]"
            errlog.log(msg)
            raise TaskQueueException(e, msg, traceback.format_exc())

        return None

    def change_visibility(
        self, message_handle_id, visibility_timeout_sec, task_priority=None
    ) -> None:
        """Changes visibility timeout of the message by its handle id

        Args:
            message_handle_id(str): the sqs handler associated of the message to be deleted
            task_priority(int): <Interface argument, not used in this class>

        Returns: None
        """

        try:
            self.sqs_client.change_message_visibility(
                QueueUrl=self.sqs_queue.url,
                ReceiptHandle=message_handle_id,
                VisibilityTimeout=visibility_timeout_sec,
            )

        except Exception as e:
            msg = f"QueueSQS: Cannot reset VTO for message handle id {message_handle_id}, Exception: [{e}] [{traceback.format_exc()}]"
            errlog.log(msg)
            raise TaskQueueException(e, msg, traceback.format_exc())

        return None

    def get_queue_length(self) -> int:
        queue_length = int(self.sqs_queue.attributes.get("ApproximateNumberOfMessages"))
        return queue_length
