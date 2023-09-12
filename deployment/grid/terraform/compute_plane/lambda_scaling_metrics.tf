# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


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
  handler                           = "scaling_metrics.lambda_handler"
  memory_size                       = 1024
  timeout                           = 60
  runtime                           = var.lambda_runtime
  create_role                       = false
  lambda_role                       = aws_iam_role.role_scaling_metrics.arn
  use_existing_cloudwatch_log_group = false

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
  name                = "scaling_metrics_event_rule-${local.suffix}"
  description         = "Fires event rule to put metrics"
  schedule_expression = var.metrics_event_rule_time
}


resource "aws_cloudwatch_event_target" "check_scaling_metrics_lambda" {
  rule      = aws_cloudwatch_event_rule.scaling_metrics_event_rule.name
  target_id = "lambda"
  arn       = module.scaling_metrics.lambda_function_arn
}


resource "aws_lambda_permission" "allow_cloudwatch_to_call_check_scaling_metrics_lambda" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = module.scaling_metrics.lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.scaling_metrics_event_rule.arn
}


# Lambda Scaling Metrics IAM Role & Permissions
resource "aws_iam_role" "role_scaling_metrics" {
  name               = "role_scaling_metrics-${local.suffix}"
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


resource "aws_iam_policy" "scaling_metrics_logging_policy" {
  name        = "scaling_metrics_logging_policy-${local.suffix}"
  path        = "/"
  description = "IAM policy for logging from the scaling_metrics lambda"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:${local.partition}:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}


resource "aws_iam_policy" "scaling_metrics_data_policy" {
  name        = "scaling_metrics_data_policy-${local.suffix}"
  path        = "/"
  description = "IAM policy for accessing DDB and SQS from a lambda"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "dynamodb:*",
        "sqs:*",
        "cloudwatch:PutMetricData",
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


resource "aws_iam_role_policy_attachment" "scaling_metrics_logs_attachment" {
  role       = aws_iam_role.role_scaling_metrics.name
  policy_arn = aws_iam_policy.scaling_metrics_logging_policy.arn
}


resource "aws_iam_role_policy_attachment" "scaling_metrics_data_attachment" {
  role       = aws_iam_role.role_scaling_metrics.name
  policy_arn = aws_iam_policy.scaling_metrics_data_policy.arn
}
