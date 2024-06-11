# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


module "ttl_checker_cloudwatch_kms_key" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 2.0"

  description             = "CMK KMS Key used to encrypt ttl_checker CloudWatch Logs"
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
          values   = ["arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/${var.lambda_name_ttl_checker}"]
        }
      ]
    }
  ]

  aliases = ["cloudwatch/lambda/${var.lambda_name_ttl_checker}"]
}


module "ttl_checker" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 5.0"

  source_path = [
    "../../../source/control_plane/python/lambda/ttl_checker",
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
      pip_requirements = "../../../source/control_plane/python/lambda/ttl_checker/requirements.txt"
    }
  ]
  function_name   = var.lambda_name_ttl_checker
  build_in_docker = true
  docker_image    = local.lambda_build_runtime
  docker_additional_options = [
    "--platform", "linux/amd64",
  ]
  handler     = "ttl_checker.lambda_handler"
  memory_size = 1024
  timeout     = 55
  runtime     = var.lambda_runtime

  role_name             = "role_lambda_ttl_checker_${local.suffix}"
  role_description      = "Lambda role for ttl_checker-${local.suffix}"
  attach_network_policy = true

  attach_policies    = true
  number_of_policies = 2
  policies = [
    aws_iam_policy.lambda_data_policy.arn,
    aws_iam_policy.lambda_cloudwatch_policy.arn
  ]

  attach_cloudwatch_logs_policy = true
  cloudwatch_logs_kms_key_id    = module.ttl_checker_cloudwatch_kms_key.key_arn

  attach_tracing_policy = true
  tracing_mode          = "Active"

  vpc_subnet_ids         = var.vpc_private_subnet_ids
  vpc_security_group_ids = [var.vpc_default_security_group_id]

  environment_variables = {
    STATE_TABLE_NAME                             = var.ddb_state_table,
    STATE_TABLE_SERVICE                          = var.state_table_service,
    STATE_TABLE_CONFIG                           = var.state_table_config,
    TASKS_QUEUE_NAME                             = element(local.htc_task_queue_names, 0),
    TASKS_QUEUE_DLQ_NAME                         = element(local.htc_task_queue_dlq_names, 0),
    METRICS_ARE_ENABLED                          = var.metrics_are_enabled,
    TASK_QUEUE_SERVICE                           = var.task_queue_service,
    TASK_QUEUE_CONFIG                            = var.task_queue_config,
    METRICS_TTL_CHECKER_LAMBDA_CONNECTION_STRING = var.metrics_ttl_checker_lambda_connection_string,
    ERROR_LOG_GROUP                              = var.error_log_group,
    ERROR_LOGGING_STREAM                         = var.error_logging_stream,
    METRICS_GRAFANA_PRIVATE_IP                   = var.nlb_influxdb,
    REGION                                       = var.region
  }

  tags = {
    service = "htc-grid"
  }
}


resource "aws_cloudwatch_event_rule" "ttl_checker_event_rule" {
  name                = "ttl_checker_event_rule-${local.suffix}"
  description         = "Fires event to trigger TTL Checker Lambda"
  schedule_expression = "rate(1 minute)"
}


resource "aws_cloudwatch_event_target" "ttl_checker_event_target" {
  rule      = aws_cloudwatch_event_rule.ttl_checker_event_rule.name
  target_id = "lambda"
  arn       = module.ttl_checker.lambda_function_arn
}


resource "aws_lambda_permission" "allow_cloudwatch_to_call_ttl_checker_lambda" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = module.ttl_checker.lambda_function_arn
  principal     = "events.${local.dns_suffix}"
  source_arn    = aws_cloudwatch_event_rule.ttl_checker_event_rule.arn
}


resource "aws_iam_policy" "lambda_cloudwatch_policy" {
  name        = "lambda_cloudwatch_policy-${local.suffix}"
  path        = "/"
  description = "IAM policy to access cloud watch metrics by TTL Lambda"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "cloudwatch:GetMetricStatistics"
      ],
      "Resource": "*",
      "Effect": "Allow"
    }
  ]
}
EOF
}
