# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import boto3
from botocore.exceptions import ClientError

import logging
from utils import grid_error_logger as errlog

logging.basicConfig(format="%(asctime)s - %(levelname)s - %(filename)s - %(funcName)s  - %(lineno)d - %(message)s",
                    datefmt='%H:%M:%S', level=logging.INFO)


class QueueSQS:

    def __init__(self, endpoint_url, queue_name, region):
        # Connection + Authentication

        logging.info(f"Initializing QueueSQS: {endpoint_url} {queue_name} {region}")

        self.endpoint_url = endpoint_url

        self.queue_name = queue_name

        try:

            sqs_resource = boto3.resource('sqs', region_name=region, endpoint_url=endpoint_url)

            self.sqs_queue = sqs_resource.get_queue_by_name(QueueName=queue_name)

            self.sqs_client = boto3.client('sqs', region_name=region, endpoint_url=endpoint_url)

        except Exception as e:
            errlog.log("QueueSQS: cannot connect to queue_name [{}], endpoint_url [{}] region [{}] : {}".format(
                queue_name, endpoint_url, region, e))
            raise e

    # Single write &  Batch write
    def send_messages(self, message_bodies=[], message_attributes={}):

        response = self.sqs_queue.send_messages(
            Entries=message_bodies
        )

        return response

        # return {
        #     'Successful': [
        #         {
        #             'Id': str,
        #         }
        #     ],
        #     'Failed': [
        #         {
        #             'Id': str,
        #         }
        #     ]
        # }

    def receive_message(self, wait_time_sec=0):

        messages = self.sqs_queue.receive_messages(MaxNumberOfMessages=1, WaitTimeSeconds=wait_time_sec)

        if len(messages) == 0:
            # No messages were returned
            return {}

        return {
            "body": messages[0].body,
            "properties": {
                "message_handle_id": messages[0].receipt_handle
            }
        }

    def delete_message(self, message_handle_id, task_priority=None):
        """Deletes message from the queue by the message_handle_id.
        Often this function is called when message is successfully consumed.

        Args:
        message_handle_id(str): the sqs handler associated of the message to be deleted
        task_priority(int): <Interface argument, not used in this class>

        Returns: None

        Raises: ClientError: if message can not be deleted
        """

        try:
            self.sqs_client.delete_message(
                QueueUrl=self.sqs_queue.url,
                ReceiptHandle=message_handle_id
            )

        except ClientError as e:
            errlog.log("Cannot delete message by handle id {} : {}".format(message_handle_id, e))
            raise e

        return None

    def change_visibility(self, message_handle_id, visibility_timeout_sec, task_priority=None):
        """Changes visibility timeout of the message by its handle

        Args:
        message_handle_id(str): the sqs handler associated of the message to be deleted
        task_priority(int): <Interface argument, not used in this class>

        Returns: None

        Raises: ClientError: on failure
        """

        try:

            self.sqs_client.change_message_visibility(
                QueueUrl=self.sqs_queue.url,
                ReceiptHandle=message_handle_id,
                VisibilityTimeout=visibility_timeout_sec
            )
        except ClientError as e:
            errlog.log("Cannot reset VTO for message {} : {}".format(message_handle_id, e))
            raise e

        return None

    def get_queue_length(self):
        queue_length = int(self.sqs_queue.attributes.get('ApproximateNumberOfMessages'))
        return queue_length
