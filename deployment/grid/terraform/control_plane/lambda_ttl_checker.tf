# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


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
  create_role = false
  lambda_role = aws_iam_role.role_lambda_ttl_checker.arn

  vpc_subnet_ids         = var.vpc_private_subnet_ids
  vpc_security_group_ids = [var.vpc_default_security_group_id]

  environment_variables = {
    STATE_TABLE_NAME                             = var.ddb_state_table,
    STATE_TABLE_SERVICE                          = var.state_table_service,
    STATE_TABLE_CONFIG                           = var.state_table_config,
    TASKS_QUEUE_NAME                             = aws_sqs_queue.htc_task_queue["__0"].name,
    TASKS_QUEUE_DLQ_NAME                         = aws_sqs_queue.htc_task_queue_dlq.name
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


#Lambda TTL Checker IAM Role & Permissions
resource "aws_iam_role" "role_lambda_ttl_checker" {
  name               = "role_lambda_ttl_checker-${local.suffix}"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
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
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ttl_checker_event_rule.arn
}


resource "aws_iam_role_policy_attachment" "ttl_checker_lambda_logs_attachment" {
  role       = aws_iam_role.role_lambda_ttl_checker.name
  policy_arn = aws_iam_policy.lambda_logging_policy.arn
}


resource "aws_iam_role_policy_attachment" "ttl_checker_lambda_data_attachment" {
  role       = aws_iam_role.role_lambda_ttl_checker.name
  policy_arn = aws_iam_policy.lambda_data_policy.arn
}


resource "aws_iam_role_policy_attachment" "ttl_checker_lambda_cludwatch_attachment" {
  role       = aws_iam_role.role_lambda_ttl_checker.name
  policy_arn = aws_iam_policy.lambda_cloudwatch_policy.arn
}
