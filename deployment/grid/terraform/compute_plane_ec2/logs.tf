# Copyright 2024 Amazon.com, Inc. or its affiliates.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

# Dedicated CMK for the worker container-log group. CloudWatch Logs requires the
# logs.<region> service principal to be allowed on the key, so we create a purpose-built
# key (repo convention: every module owns its CMK) rather than reuse a data/SSM key.
module "worker_logs_kms_key" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 2.0"

  description             = "CMK for HTC-Grid EC2 worker CloudWatch container logs"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  key_administrators = var.kms_key_admin_arns

  key_statements = [
    {
      sid     = "AllowCloudWatchLogs"
      actions = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
      effect  = "Allow"
      principals = [
        {
          type        = "Service"
          identifiers = ["logs.${var.region}.${local.dns_suffix}"]
        }
      ]
      resources = ["*"]
      conditions = [
        {
          test     = "ArnEquals"
          variable = "kms:EncryptionContext:aws:logs:arn"
          values   = ["arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:${local.worker_log_group_name}"]
        }
      ]
    }
  ]

  aliases = ["cloudwatch/htc-ec2-worker-${local.suffix}"]
}

# Dedicated container-log group for the ec2 worker plane (parallel to the EKS
# fluentbit group). The Compose awslogs driver ships agent/rie/getlayer stdout here.
resource "aws_cloudwatch_log_group" "worker_logs" {
  name              = local.worker_log_group_name
  retention_in_days = 30
  kms_key_id        = module.worker_logs_kms_key.key_arn
}
