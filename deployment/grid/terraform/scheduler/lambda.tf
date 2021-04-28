# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/




resource "aws_iam_role" "role_lambda_submit_task" {
  name = "role_lambda_submit_task-${local.suffix}"
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

resource "aws_iam_role" "role_lambda_get_results" {
  name = "role_lambda_get_results-${local.suffix}"
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

resource "aws_iam_role" "role_lambda_cancel_tasks" {
  name = "role_lambda_cancel_tasks-${local.suffix}"
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


resource "aws_iam_role" "role_lambda_ttl_checker" {
  name = "role_lambda_ttl_checker-${local.suffix}"
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

module "submit_task" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "v1.48.0"
  source_path = [
    "../../../source/control_plane/python/lambda/submit_tasks",
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
      pip_requirements = "../../../source/control_plane/python/lambda/submit_tasks/requirements.txt"
    }
  ]
  function_name = var.lambda_name_submit_tasks
  build_in_docker = true
  docker_image = "${var.aws_htc_ecr}/lambda-build:build-${var.lambda_runtime}"
  handler = "submit_tasks.lambda_handler"
  memory_size = 1024
  timeout = 300
  runtime = var.lambda_runtime
  create_role = false
  lambda_role = aws_iam_role.role_lambda_submit_task.arn

  vpc_subnet_ids = var.vpc_private_subnet_ids
  vpc_security_group_ids = [var.vpc_default_security_group_id]

  environment_variables  = {
    TASKS_STATUS_TABLE_NAME=aws_dynamodb_table.htc_tasks_status_table.name,
    TASKS_QUEUE_NAME=aws_sqs_queue.htc_task_queue.name,
    TASKS_QUEUE_DLQ_NAME=aws_sqs_queue.htc_task_queue_dlq.name,
    METRICS_ARE_ENABLED=var.metrics_are_enabled,
    METRICS_SUBMIT_TASKS_LAMBDA_CONNECTION_STRING=var.metrics_submit_tasks_lambda_connection_string,
    ERROR_LOG_GROUP=var.error_log_group,
    ERROR_LOGGING_STREAM=var.error_logging_stream,
    TASK_INPUT_PASSED_VIA_EXTERNAL_STORAGE = var.task_input_passed_via_external_storage,
    GRID_STORAGE_SERVICE = var.grid_storage_service,
    S3_BUCKET = aws_s3_bucket.htc-stdout-bucket.id,
    REDIS_URL = aws_elasticache_cluster.stdin-stdout-cache.cache_nodes.0.address,
    METRICS_GRAFANA_PRIVATE_IP = var.nlb_influxdb,
    REGION = var.region
  }

   tags = {
    service     = "htc-grid"
  }
  #depends_on = [aws_iam_role_policy_attachment.lambda_logs_attachment, aws_cloudwatch_log_group.submit_task_logs]
}

module  "get_results" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "v1.48.0"
  source_path = [
    "../../../source/control_plane/python/lambda/get_results",
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
      pip_requirements = "../../../source/control_plane/python/lambda/get_results/requirements.txt"
    }
  ]
  function_name = var.lambda_name_get_results
  build_in_docker = true
  docker_image = "${var.aws_htc_ecr}/lambda-build:build-${var.lambda_runtime}"
  handler = "get_results.lambda_handler"
  memory_size = 1024
  timeout = 300
  runtime = var.lambda_runtime
  create_role = false
  lambda_role = aws_iam_role.role_lambda_get_results.arn
  vpc_subnet_ids = var.vpc_private_subnet_ids
  vpc_security_group_ids = [var.vpc_default_security_group_id]
  environment_variables = {
    TASKS_STATUS_TABLE_NAME=aws_dynamodb_table.htc_tasks_status_table.name,
    TASKS_QUEUE_NAME=aws_sqs_queue.htc_task_queue.name,
    S3_BUCKET=aws_s3_bucket.htc-stdout-bucket.id,
    REDIS_URL=aws_elasticache_cluster.stdin-stdout-cache.cache_nodes.0.address,
    GRID_STORAGE_SERVICE=var.grid_storage_service,
    TASKS_QUEUE_DLQ_NAME = aws_sqs_queue.htc_task_queue_dlq.name,
    METRICS_ARE_ENABLED = var.metrics_are_enabled,
    METRICS_GET_RESULTS_LAMBDA_CONNECTION_STRING = var.metrics_get_results_lambda_connection_string,
    ERROR_LOG_GROUP=var.error_log_group,
    ERROR_LOGGING_STREAM=var.error_logging_stream,
    METRICS_GRAFANA_PRIVATE_IP = var.nlb_influxdb,
    REGION = var.region
  }
   tags = {
    service     = "htc-grid"
  }
  #depends_on = [aws_iam_role_policy_attachment.lambda_logs_attachment, aws_cloudwatch_log_group.submit_task_logs]
}

module "cancel_tasks" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "v1.48.0"
  source_path = [
    "../../../source/control_plane/python/lambda/cancel_tasks",
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
      pip_requirements = "../../../source/control_plane/python/lambda/cancel_tasks/requirements.txt"
    }
  ]
  function_name = var.lambda_name_cancel_tasks
  build_in_docker = true
  docker_image = "${var.aws_htc_ecr}/lambda-build:build-${var.lambda_runtime}"
  handler = "cancel_tasks.lambda_handler"
  memory_size = 1024
  timeout = 300
  runtime = var.lambda_runtime
  create_role = false
  lambda_role = aws_iam_role.role_lambda_cancel_tasks.arn

  vpc_subnet_ids = var.vpc_private_subnet_ids
  vpc_security_group_ids = [var.vpc_default_security_group_id]

  environment_variables  = {
    TASKS_STATUS_TABLE_NAME=aws_dynamodb_table.htc_tasks_status_table.name,
    TASKS_QUEUE_NAME=aws_sqs_queue.htc_task_queue.name,
    TASKS_QUEUE_DLQ_NAME=aws_sqs_queue.htc_task_queue_dlq.name,
    METRICS_ARE_ENABLED=var.metrics_are_enabled,
    METRICS_CANCEL_TASKS_LAMBDA_CONNECTION_STRING=var.metrics_cancel_tasks_lambda_connection_string,
    ERROR_LOG_GROUP=var.error_log_group,
    ERROR_LOGGING_STREAM=var.error_logging_stream,
    TASK_INPUT_PASSED_VIA_EXTERNAL_STORAGE = var.task_input_passed_via_external_storage,
    GRID_STORAGE_SERVICE = var.grid_storage_service,
    S3_BUCKET = aws_s3_bucket.htc-stdout-bucket.id,
    REDIS_URL = aws_elasticache_cluster.stdin-stdout-cache.cache_nodes.0.address,
    METRICS_GRAFANA_PRIVATE_IP = var.nlb_influxdb,
    REGION = var.region
  }

   tags = {
    service     = "htc-grid"
  }
  #depends_on = [aws_iam_role_policy_attachment.lambda_logs_attachment, aws_cloudwatch_log_group.cancel_tasks_logs]
}



module "ttl_checker" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "v1.48.0"
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
  function_name = var.lambda_name_ttl_checker
  build_in_docker = true
  docker_image = "${var.aws_htc_ecr}/lambda-build:build-${var.lambda_runtime}"
  handler = "ttl_checker.lambda_handler"
  memory_size = 1024
  timeout = 55
  runtime = var.lambda_runtime
  create_role = false
  lambda_role = aws_iam_role.role_lambda_ttl_checker.arn

  vpc_subnet_ids = var.vpc_private_subnet_ids
  vpc_security_group_ids = [var.vpc_default_security_group_id]

  use_existing_cloudwatch_log_group = true
  environment_variables = {
    TASKS_STATUS_TABLE_NAME=aws_dynamodb_table.htc_tasks_status_table.name,
    TASKS_QUEUE_NAME=aws_sqs_queue.htc_task_queue.name,
    TASKS_QUEUE_DLQ_NAME=aws_sqs_queue.htc_task_queue_dlq.name
    METRICS_ARE_ENABLED=var.metrics_are_enabled,
    METRICS_TTL_CHECKER_LAMBDA_CONNECTION_STRING=var.metrics_ttl_checker_lambda_connection_string,
    ERROR_LOG_GROUP=var.error_log_group,
    ERROR_LOGGING_STREAM=var.error_logging_stream,
    METRICS_GRAFANA_PRIVATE_IP = var.nlb_influxdb,
    REGION = var.region
  }

   tags = {
    service     = "htc-grid"
  }
  depends_on = [
    aws_cloudwatch_log_group.ttl_log
  ]

}

resource "aws_cloudwatch_log_group" "ttl_log" {
  name = "/aws/lambda/${var.lambda_name_ttl_checker}"
  retention_in_days = 5
}

resource "aws_cloudwatch_event_rule" "ttl_checker_event_rule" {
  name                = "ttl_checker_event_rule-${local.suffix}"
  description         = "Fires event to trigger TTL Checker Lambda"
  schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "ttl_checker_event_target" {
  rule      = aws_cloudwatch_event_rule.ttl_checker_event_rule.name
  target_id = "lambda"
  arn       = module.ttl_checker.this_lambda_function_arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_ttl_checker_lambda" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = module.ttl_checker.this_lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ttl_checker_event_rule.arn
}

resource "aws_cloudwatch_log_group" "global_error_group" {
   name = var.error_log_group
   retention_in_days = 14
}

resource "aws_cloudwatch_log_stream" "global_error_stream" {
   name = var.error_logging_stream
   log_group_name  = aws_cloudwatch_log_group.global_error_group.name
}

resource "aws_iam_policy" "lambda_logging_policy" {
  name        = "lambda_logging_policy-${local.suffix}"
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
  policy = <<EOF
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


resource "aws_iam_role_policy_attachment" "lambda_logs_attachment" {
  role       = aws_iam_role.role_lambda_submit_task.name
  policy_arn = aws_iam_policy.lambda_logging_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_data_attachment" {
  role       = aws_iam_role.role_lambda_submit_task.name
  policy_arn = aws_iam_policy.lambda_data_policy.arn
}


resource "aws_iam_role_policy_attachment" "get_results_lambda_logs_attachment" {
  role       = aws_iam_role.role_lambda_get_results.name
  policy_arn = aws_iam_policy.lambda_logging_policy.arn
}

resource "aws_iam_role_policy_attachment" "get_results_lambda_data_attachment" {
  role       = aws_iam_role.role_lambda_get_results.name
  policy_arn = aws_iam_policy.lambda_data_policy.arn
}


resource "aws_iam_role_policy_attachment" "cancel_tasks_lambda_logs_attachment" {
  role       = aws_iam_role.role_lambda_cancel_tasks.name
  policy_arn = aws_iam_policy.lambda_logging_policy.arn
}

resource "aws_iam_role_policy_attachment" "cancel_tasks_lambda_data_attachment" {
  role       = aws_iam_role.role_lambda_cancel_tasks.name
  policy_arn = aws_iam_policy.lambda_data_policy.arn
}


resource "aws_iam_role_policy_attachment" "ttl_checker_lambda_logs_attachment" {
  role       = aws_iam_role.role_lambda_ttl_checker.name
  policy_arn = aws_iam_policy.lambda_logging_policy.arn
}

resource "aws_iam_role_policy_attachment" "ttl_checker_lambda_data_attachment" {
  role       = aws_iam_role.role_lambda_ttl_checker.name
  policy_arn = aws_iam_policy.lambda_data_policy.arn
}