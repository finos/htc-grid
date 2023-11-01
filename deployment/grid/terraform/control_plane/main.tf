# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


locals {
  # check if var.suffix is empty then create a random suffix else use var.suffix
  suffix               = var.suffix != "" ? var.suffix : random_string.random.result
  account_id           = data.aws_caller_identity.current.account_id
  dns_suffix           = data.aws_partition.current.dns_suffix
  partition            = data.aws_partition.current.partition
  lambda_build_runtime = "${var.aws_htc_ecr}/ecr-public/sam/build-${var.lambda_runtime}:1"
}


# Retrieve the account ID
data "aws_caller_identity" "current" {}


# Retrieve AWS Partition
data "aws_partition" "current" {}


resource "random_string" "random" {
  length  = 10
  special = false
  upper   = false
}


# Lambda CloudWatch Config & Permissions
module "global_error_cloudwatch_kms_key" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 2.0"

  description             = "CMK to encrypt global_error CloudWatch Logs"
  deletion_window_in_days = 7

  key_administrators = [
    "arn:${local.partition}:iam::${local.account_id}:root",
    data.aws_caller_identity.current.arn
  ]

  key_statements = [
    {
      sid = "Allow Lambda functions & Agent to encrypt/decrypt CloudWatch Logs"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
        "kms:Decrypt",
      ]
      effect = "Allow"
      principals = [
        {
          type = "Service"
          identifiers = [
            "logs.${var.region}.amazonaws.com"
          ]
        }
      ]
      resources = ["*"]
      condition = [
        {
          test     = "ArnLike"
          variable = "kms:EncryptionContext:aws:logs:arn"
          values   = ["arn:${local.partition}:logs:${var.region}:${local.account_id}:*"]
        }
      ]
    }
  ]

  aliases = ["cloudwatch/lambda/global_error-${local.suffix}"]
}


resource "aws_cloudwatch_log_group" "global_error_group" {
  name              = var.error_log_group
  retention_in_days = 14
  kms_key_id = module.global_error_cloudwatch_kms_key.key_arn
}


resource "aws_cloudwatch_log_stream" "global_error_stream" {
  name           = var.error_logging_stream
  log_group_name = aws_cloudwatch_log_group.global_error_group.name
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
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ],
      "Resource": "*",
      "Effect": "Allow"
    }
  ]
}
EOF
}
