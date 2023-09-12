# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


module "cancel_tasks" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 5.0"

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

  function_name   = var.lambda_name_cancel_tasks
  build_in_docker = true
  docker_image    = local.lambda_build_runtime
  docker_additional_options = [
    "--platform", "linux/amd64",
  ]
  handler     = "cancel_tasks.lambda_handler"
  memory_size = 1024
  timeout     = 300
  runtime     = var.lambda_runtime
  create_role = false
  lambda_role = aws_iam_role.role_lambda_cancel_tasks.arn

  vpc_subnet_ids         = var.vpc_private_subnet_ids
  vpc_security_group_ids = [var.vpc_default_security_group_id]

  environment_variables = {
    STATE_TABLE_NAME                              = var.ddb_state_table,
    STATE_TABLE_SERVICE                           = var.state_table_service,
    STATE_TABLE_CONFIG                            = var.state_table_config,
    TASKS_QUEUE_NAME                              = aws_sqs_queue.htc_task_queue["__0"].name,
    TASKS_QUEUE_DLQ_NAME                          = aws_sqs_queue.htc_task_queue_dlq.name,
    METRICS_ARE_ENABLED                           = var.metrics_are_enabled,
    METRICS_CANCEL_TASKS_LAMBDA_CONNECTION_STRING = var.metrics_cancel_tasks_lambda_connection_string,
    ERROR_LOG_GROUP                               = var.error_log_group,
    ERROR_LOGGING_STREAM                          = var.error_logging_stream,
    TASK_INPUT_PASSED_VIA_EXTERNAL_STORAGE        = var.task_input_passed_via_external_storage,
    GRID_STORAGE_SERVICE                          = var.grid_storage_service,
    TASK_QUEUE_SERVICE                            = var.task_queue_service,
    TASK_QUEUE_CONFIG                             = var.task_queue_config,
    S3_BUCKET                                     = aws_s3_bucket.htc-stdout-bucket.id,
    REDIS_URL                                     = aws_elasticache_cluster.stdin-stdout-cache.cache_nodes.0.address,
    METRICS_GRAFANA_PRIVATE_IP                    = var.nlb_influxdb,
    REGION                                        = var.region
  }

  tags = {
    service = "htc-grid"
  }
}


#Lambda Cancel Tasks IAM Role & Permissions
resource "aws_iam_role" "role_lambda_cancel_tasks" {
  name               = "role_lambda_cancel_tasks-${local.suffix}"
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



resource "aws_iam_role_policy_attachment" "cancel_tasks_lambda_logs_attachment" {
  role       = aws_iam_role.role_lambda_cancel_tasks.name
  policy_arn = aws_iam_policy.lambda_logging_policy.arn
}


resource "aws_iam_role_policy_attachment" "cancel_tasks_lambda_data_attachment" {
  role       = aws_iam_role.role_lambda_cancel_tasks.name
  policy_arn = aws_iam_policy.lambda_data_policy.arn
}
