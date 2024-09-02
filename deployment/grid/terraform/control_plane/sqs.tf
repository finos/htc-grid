# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


locals {
  htc_task_queue_names     = [for k, v in aws_sqs_queue.htc_task_queue : v.name]
  htc_task_queue_dlq_names = [for k, v in aws_sqs_queue.htc_task_queue_dlq : v.name]
}


module "htc_task_queue_kms_key" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 2.0"

  description             = "CMK KMS Key to encrypt SQS Queues"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true
  enable_default_policy   = false

  key_administrators = local.kms_key_admin_arns

  key_statements = [
    {
      sid    = "Allow CMK KMS Key Access via SQS Service"
      effect = "Allow"
      actions = [
        "kms:Encrypt*",
        "kms:Decrypt*",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:Describe*"
      ]
      resources = ["*"]

      principals = [
        {
          type        = "AWS"
          identifiers = local.kms_key_admin_arns
        }
      ]

      conditions = [
        {
          test     = "StringEquals"
          variable = "kms:ViaService"
          values = [
            "sqs.${var.region}.${local.dns_suffix}"
          ]
        }
      ]
    }
  ]

  aliases = ["sqs/htc_task_queue_${local.suffix}"]
}


resource "aws_sqs_queue" "htc_task_queue" {
  for_each = var.priorities

  name                              = format("%s%s", var.sqs_queue, each.key)
  message_retention_seconds         = 1209600 # max 14 days
  visibility_timeout_seconds        = 40      # once acquired we should update visibility timeout during processing
  kms_master_key_id                 = module.htc_task_queue_kms_key.key_arn
  kms_data_key_reuse_period_seconds = 300

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.htc_task_queue_dlq[each.key].arn
    maxReceiveCount     = 4
  })

  tags = {
    service = "htc-aws"
  }
}


resource "aws_sqs_queue_policy" "htc_task_queue_policy" {
  for_each  = var.priorities
  queue_url = aws_sqs_queue.htc_task_queue[each.key].id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Id": "sqspolicy",
  "Statement": [
    {
      "Sid": "HTTPSOnly",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "sqs:*",
      "Resource": "${aws_sqs_queue.htc_task_queue[each.key].arn}",
      "Condition": {
        "Bool": {
          "aws:SecureTransport": false
        }
      }
    }
  ]
}
EOF
}


module "htc_task_queue_dlq_kms_key" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 2.0"

  description             = "CMK KMS Key to encrypt SQS DLQ Queues"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true
  enable_default_policy   = false

  key_administrators = local.kms_key_admin_arns

  key_statements = [
    {
      sid    = "Allow CMK KMS Key Access via SQS Service"
      effect = "Allow"
      actions = [
        "kms:Encrypt*",
        "kms:Decrypt*",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:Describe*"
      ]
      resources = ["*"]

      principals = [
        {
          type        = "AWS"
          identifiers = local.kms_key_admin_arns
        }
      ]

      conditions = [
        {
          test     = "StringEquals"
          variable = "kms:ViaService"
          values = [
            "sqs.${var.region}.${local.dns_suffix}"
          ]
        }
      ]
    }
  ]

  aliases = ["sqs/htc_task_queue_dlq_${local.suffix}"]
}


resource "aws_sqs_queue" "htc_task_queue_dlq" {
  for_each = var.priorities

  name                              = format("%s%s", var.sqs_dlq, each.key)
  message_retention_seconds         = 1209600 # max 14 days
  kms_master_key_id                 = module.htc_task_queue_dlq_kms_key.key_arn
  kms_data_key_reuse_period_seconds = 300

  tags = {
    service = "htc-aws"
  }
}


resource "aws_sqs_queue_policy" "htc_task_queue_dlq_policy" {
  for_each  = var.priorities
  queue_url = aws_sqs_queue.htc_task_queue_dlq[each.key].id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Id": "sqspolicy",
  "Statement": [
    {
      "Sid": "HTTPSOnly",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "sqs:*",
      "Resource": "${aws_sqs_queue.htc_task_queue_dlq[each.key].arn}",
      "Condition": {
        "Bool": {
          "aws:SecureTransport": false
        }
      }
    }
  ]
}
EOF
}
