# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


module "scaling_metrics_cloudwatch_kms_key" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 2.0"

  description             = "CMK KMS Key used to encrypt scaling_metrics CloudWatch Logs"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true

  key_administrators = local.kms_key_admin_arns

  key_statements = [
    {
      sid = "Allow Lambda functions to encrypt/decrypt CloudWatch Logs"
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
            "logs.${var.region}.${local.dns_suffix}"
          ]
        }
      ]
      resources = ["*"]
      conditions = [
        {
          test     = "ArnEquals"
          variable = "kms:EncryptionContext:aws:logs:arn"
          values   = ["arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/${var.lambda_name_scaling_metrics}"]
        }
      ]
    }
  ]

  aliases = ["cloudwatch/lambda/${var.lambda_name_scaling_metrics}"]
}


module "scaling_metrics" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 5.0"

  source_path = [
    "../../../source/compute_plane/python/lambda/scaling_metrics/",
    {
      path = "../../../source/client/python/api-v0.1/"
      patterns = [
        "!README\\.md",
        "!setup\\.py",
        "!LICENSE*",
      ]
    },
    {
      path = "../../../source/client/python/utils/"
      patterns = [
        "!README\\.md",
        "!setup\\.py",
        "!LICENSE*",
      ]
    },
    {
      pip_requirements = "../../../source/compute_plane/python/lambda/scaling_metrics/requirements.txt"
    }
  ]

  function_name   = var.lambda_name_scaling_metrics
  build_in_docker = true
  docker_image    = local.lambda_build_runtime
  docker_additional_options = [
    "--platform", "linux/amd64",
  ]
  handler     = "scaling_metrics.lambda_handler"
  memory_size = 1024
  timeout     = 60
  runtime     = var.lambda_runtime

  role_name             = "role_scaling_metrics_${local.suffix}"
  role_description      = "Lambda role for scaling_metrics-${local.suffix}"
  attach_network_policy = true

  attach_policies    = true
  number_of_policies = 2
  policies = [
    aws_iam_policy.lambda_data_policy.arn,
    aws_iam_policy.scaling_metrics_cloudwatch_policy.arn
  ]

  attach_cloudwatch_logs_policy = true
  cloudwatch_logs_kms_key_id    = module.scaling_metrics_cloudwatch_kms_key.key_arn

  attach_tracing_policy = true
  tracing_mode          = "Active"

  environment_variables = {
    STATE_TABLE_CONFIG   = var.ddb_state_table,
    NAMESPACE            = var.namespace_metrics,
    DIMENSION_NAME       = var.dimension_name_metrics,
    DIMENSION_VALUE      = var.cluster_name,
    PERIOD               = var.period_metrics,
    METRICS_NAME         = var.metric_name,
    SQS_QUEUE_NAME       = var.sqs_queue,
    REGION               = var.region
    TASK_QUEUE_SERVICE   = var.task_queue_service,
    TASK_QUEUE_CONFIG    = var.task_queue_config,
    ERROR_LOG_GROUP      = var.error_log_group,
    ERROR_LOGGING_STREAM = var.error_logging_stream,
    TASKS_QUEUE_NAME     = var.tasks_queue_name,
  }

  tags = {
    service = "htc-grid"
  }
}


resource "aws_cloudwatch_event_rule" "scaling_metrics_event_rule" {
  name                = "scaling_metrics_event_rule_${local.suffix}"
  description         = "Fires event rule to put metrics"
  schedule_expression = var.metrics_event_rule_time
}


resource "aws_cloudwatch_event_target" "check_scaling_metrics_lambda" {
  rule      = aws_cloudwatch_event_rule.scaling_metrics_event_rule.name
  target_id = "lambda"
  arn       = module.scaling_metrics.lambda_function_arn
}


resource "aws_lambda_permission" "allow_cloudwatch_to_call_scaling_metrics_lambda" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = module.scaling_metrics.lambda_function_name
  principal     = "events.${local.dns_suffix}"
  source_arn    = aws_cloudwatch_event_rule.scaling_metrics_event_rule.arn
}


resource "aws_iam_policy" "scaling_metrics_cloudwatch_policy" {
  name        = "scaling_metrics_data_policy_${local.suffix}"
  path        = "/"
  description = "IAM policy for publishing CloudWatch Metrics from Scaling Metrics Lambda"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "cloudwatch:PutMetricData"
      ],
      "Resource": "*",
      "Effect": "Allow"
    }
  ]
}
EOF
}
