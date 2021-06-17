# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/
 


resource "aws_iam_role" "role_lambda_metrics" {
  name = "role_lambda_metrics-${local.suffix}"
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

module "scaling_metrics" {

  source  = "terraform-aws-modules/lambda/aws"
  version = "v1.48.0"
  source_path = "../../../source/compute_plane/python/lambda/scaling_metrics/"
  function_name = var.lambda_name_scaling_metrics
  handler = "scaling_metrics.lambda_handler"
  memory_size = 1024
  timeout = 60
  runtime = var.lambda_runtime
  create_role = false
  lambda_role = aws_iam_role.role_lambda_metrics.arn

  vpc_subnet_ids = var.vpc_private_subnet_ids
  vpc_security_group_ids = [var.vpc_default_security_group_id]
  build_in_docker = true
  docker_image =  "${var.aws_htc_ecr}/lambda-build:build-${var.lambda_runtime}"
  use_existing_cloudwatch_log_group = true
  environment_variables = {
    TASKS_STATUS_TABLE_NAME=var.ddb_status_table,
    NAMESPACE=var.namespace_metrics,
    DIMENSION_NAME=var.dimension_name_metrics,
    DIMENSION_VALUE=var.cluster_name,
    PERIOD=var.period_metrics,
    METRICS_NAME=var.metric_name,
    SQS_QUEUE_NAME=var.sqs_queue,
    REGION = var.region
  }
   tags = {
    service     = "htc-grid"
  }
  depends_on = [aws_cloudwatch_log_group.lambda_scaling]
}

resource "aws_cloudwatch_log_group" "lambda_scaling" {
  name = "/aws/lambda/${var.lambda_name_scaling_metrics}"
  retention_in_days = 5
}


resource "aws_cloudwatch_event_rule" "scaling_metrics_event_rule" {
  name                = "scaling_metrics_event_rule-${local.suffix}"
  description         = "Fires event rule to put metrics"
  schedule_expression = var.metrics_event_rule_time
}

resource "aws_cloudwatch_event_target" "check_scaling_metrics_lambda" {
  rule      = aws_cloudwatch_event_rule.scaling_metrics_event_rule.name
  target_id = "lambda"
  arn       = module.scaling_metrics.this_lambda_function_arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_check_scaling_metrics_lambda" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = module.scaling_metrics.this_lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.scaling_metrics_event_rule.arn
}


# resource "aws_cloudwatch_log_group" "scaling_metrics_logs" {
#   name = "/aws/lambda/${aws_lambda_function.scaling_metrics.function_name}"
#   retention_in_days = 14
# }


resource "aws_iam_policy" "lambda_metrics_logging_policy" {
  name        = "lambda_metrics_logging_policy-${local.suffix}"
  path        = "/"
  description = "IAM policy for logging from a lambda"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_policy" "lambda_metrics_data_policy" {
  name        = "lambda_metrics_data_policy-${local.suffix}"
  path        = "/"
  description = "IAM policy for accessing DDB and SQS from a lambda"
  policy = <<EOF
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


resource "aws_iam_role_policy_attachment" "lambda_metrics_logs_attachment" {
  role       = aws_iam_role.role_lambda_metrics.name
  policy_arn = aws_iam_policy.lambda_metrics_logging_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_metrics_data_attachment" {
  role       = aws_iam_role.role_lambda_metrics.name
  policy_arn = aws_iam_policy.lambda_metrics_data_policy.arn
}

