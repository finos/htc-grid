# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


resource "aws_sqs_queue" "htc_task_queue" {
  name = var.sqs_queue

  message_retention_seconds = 1209600 # max 14 days
  visibility_timeout_seconds = 40  # once acquired we should update visibility timeout during processing

  tags = {
    service     = "htc-aws"
  }
}


resource "aws_sqs_queue" "htc_task_queue_dlq" {
  name = var.sqs_dlq

  message_retention_seconds = 1209600 # max 14 days

  tags = {
    service     = "htc-aws"
  }
}