# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import logging

from api.task_queue_sqs import QueueSQS
from api.task_queue_priority_sqs import QueuePrioritySQS


logging.basicConfig(
    format="%(asctime)s - %(levelname)s - %(filename)s - %(funcName)s  - %(lineno)d - %(message)s",
    datefmt="%H:%M:%S",
    level=logging.INFO,
)


def queue_manager(task_queue_service, task_queue_config, tasks_queue_name, region):
    # TODO due to the way variables are propagated from terraform to AWS Lambda and to Agent file
    # double quotes can not be escaped during the deployment. As a way around, task queue configuration is
    # passed with the single quotes and then converted into double quotes here.
    task_queue_config = task_queue_config.replace("'", '"')

    if task_queue_service == "SQS":
        logging.debug("Initializing Tasks Queue using single SQS ")
        endpoint_url = f"https://sqs.{region}.amazonaws.com"
        return QueueSQS(endpoint_url, tasks_queue_name, region)

    elif task_queue_service == "PrioritySQS":
        logging.debug("Initializing Tasks Tasks Queue using SQS Priority")
        endpoint_url = f"https://sqs.{region}.amazonaws.com"
        return QueuePrioritySQS(
            endpoint_url, task_queue_config, tasks_queue_name, region
        )
    else:
        raise NotImplementedError()
