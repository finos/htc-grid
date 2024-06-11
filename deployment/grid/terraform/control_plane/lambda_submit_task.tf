# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


module "submit_task_cloudwatch_kms_key" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 2.0"

  description             = "CMK KMS Key used to encrypt submit_task CloudWatch Logs"
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
          values   = ["arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/${var.lambda_name_submit_tasks}"]
        }
      ]
    }
  ]

  aliases = ["cloudwatch/lambda/${var.lambda_name_submit_tasks}"]
}


module "submit_task" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 5.0"

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

  function_name   = var.lambda_name_submit_tasks
  build_in_docker = true
  docker_image    = local.lambda_build_runtime
  docker_additional_options = [
    "--platform", "linux/amd64",
  ]
  handler     = "submit_tasks.lambda_handler"
  memory_size = 1024
  timeout     = 300
  runtime     = var.lambda_runtime

  role_name             = "role_lambda_submit_task_${local.suffix}"
  role_description      = "Lambda role for submit_task-${local.suffix}"
  attach_network_policy = true

  attach_policies    = true
  number_of_policies = 1
  policies = [
    aws_iam_policy.lambda_data_policy.arn
  ]

  attach_cloudwatch_logs_policy = true
  cloudwatch_logs_kms_key_id    = module.submit_task_cloudwatch_kms_key.key_arn

  attach_tracing_policy = true
  tracing_mode          = "Active"

  vpc_subnet_ids         = var.vpc_private_subnet_ids
  vpc_security_group_ids = [var.vpc_default_security_group_id]

  environment_variables = {
    STATE_TABLE_NAME                              = var.ddb_state_table,
    STATE_TABLE_SERVICE                           = var.state_table_service,
    STATE_TABLE_CONFIG                            = var.state_table_config,
    TASKS_QUEUE_NAME                              = element(local.htc_task_queue_names, 0),
    TASKS_QUEUE_DLQ_NAME                          = element(local.htc_task_queue_dlq_names, 0),
    METRICS_ARE_ENABLED                           = var.metrics_are_enabled,
    METRICS_SUBMIT_TASKS_LAMBDA_CONNECTION_STRING = var.metrics_submit_tasks_lambda_connection_string,
    ERROR_LOG_GROUP                               = var.error_log_group,
    ERROR_LOGGING_STREAM                          = var.error_logging_stream,
    TASK_INPUT_PASSED_VIA_EXTERNAL_STORAGE        = var.task_input_passed_via_external_storage,
    GRID_STORAGE_SERVICE                          = var.grid_storage_service,
    TASK_QUEUE_SERVICE                            = var.task_queue_service,
    TASK_QUEUE_CONFIG                             = var.task_queue_config,
    S3_BUCKET                                     = module.htc_data_bucket.s3_bucket_id, #aws_s3_bucket.htc_data_bucket.id,
    S3_KMS_KEY_ID                                 = module.htc_data_bucket_kms_key.key_arn,
    REDIS_URL                                     = aws_elasticache_replication_group.htc_data_cache.primary_endpoint_address,
    REDIS_PASSWORD                                = random_password.htc_data_cache_password.result,
    METRICS_GRAFANA_PRIVATE_IP                    = var.nlb_influxdb,
    REGION                                        = var.region
  }

  tags = {
    service = "htc-grid"
  }
}
