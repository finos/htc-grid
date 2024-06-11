# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import time


def lambda_handler(event, context):
    message = "Starting task processing... (args[0]) {}!".format(event)
    print(message)
    args = event["worker_arguments"]
    time.sleep(int(args[0]) / 1000)
    return int(args[0])
