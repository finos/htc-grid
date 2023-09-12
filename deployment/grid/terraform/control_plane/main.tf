# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


locals {
  # check if var.suffix is empty then create a random suffix else use var.suffix
  suffix               = var.suffix != "" ? var.suffix : random_string.random.result
  lambda_build_runtime = "${var.aws_htc_ecr}/ecr-public/sam/build-${var.lambda_runtime}:1"
}


data "aws_caller_identity" "current" {}


resource "random_string" "random" {
  length  = 10
  special = false
  upper   = false
}


# Lambda CloudWatch Config & Permissions
resource "aws_cloudwatch_log_group" "global_error_group" {
  name              = var.error_log_group
  retention_in_days = 14
}


resource "aws_cloudwatch_log_stream" "global_error_stream" {
  name           = var.error_logging_stream
  log_group_name = aws_cloudwatch_log_group.global_error_group.name
}


resource "aws_iam_policy" "lambda_logging_policy" {
  name        = "lambda_logging_policy-${local.suffix}"
  path        = "/"
  description = "IAM policy for logging from a lambda"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}


resource "aws_iam_policy" "lambda_data_policy" {
  name        = "lambda_data_policy-${local.suffix}"
  path        = "/"
  description = "IAM policy for accessing DDB and SQS from a lambda"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "sqs:*",
        "dynamodb:*",
        "firehose:*",
        "s3:*",
        "ec2:CreateNetworkInterface",
        "ec2:DeleteNetworkInterface",
        "ec2:DescribeNetworkInterfaces"
      ],
      "Resource": "*",
      "Effect": "Allow"
    }
  ]
}
EOF
}
