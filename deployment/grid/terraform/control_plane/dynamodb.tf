# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


module "htc_dynamodb_table_kms_key" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 2.0"

  description             = "CMK KMS Key used to encrypt HTC DynamoDB tables"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true

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
            "dynamodb.${var.region}.${local.dns_suffix}"
          ]
        }
      ]
    }
  ]

  aliases = ["dynamodb/${var.ddb_state_table}"]
}


module "htc_dynamodb_table" {
  source  = "terraform-aws-modules/dynamodb-table/aws"
  version = "~> 3.0"

  name = var.ddb_state_table

  autoscaling_enabled = var.dynamodb_autoscaling_enabled
  billing_mode        = var.dynamodb_billing_mode
  read_capacity       = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_table_read_capacity : null
  write_capacity      = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_table_write_capacity : null

  point_in_time_recovery_enabled = true

  server_side_encryption_enabled     = true
  server_side_encryption_kms_key_arn = module.htc_dynamodb_table_kms_key.key_arn

  hash_key = "task_id"
  attributes = [
    {
      name = "session_id"
      type = "S"
    },
    {
      name = "task_id"
      type = "S"
    },
    # {
    #   name = "submission_timestamp"
    #   type = "N"
    # },
    # {
    #   name = "task_completion_timestamp"
    #   type = "N"
    # },
    {
      name = "task_status"
      type = "S"
    },
    # {
    #   name = "task_owner"
    #   type = "S"
    # },
    # default value "None"
    # {
    #   name = "retries"
    #   type = "N"
    # },
    # {
    #   name = "task_definition"
    #   type = "S"
    # },
    # {
    #   name = "sqs_handler_id"
    #   type = "S"
    # },
    {
      name = "heartbeat_expiration_timestamp"
      type = "N"
    }
    # attribute {
    #   name = "parent_session_id"
    #   type = "S"
    # }
  ]

  global_secondary_indexes = [
    {
      name               = "gsi_ttl_index"
      hash_key           = "task_status"
      range_key          = "heartbeat_expiration_timestamp"
      read_capacity      = var.dynamodb_gsi_ttl_table_read_capacity
      write_capacity     = var.dynamodb_gsi_ttl_table_write_capacity
      projection_type    = "INCLUDE"
      non_key_attributes = ["task_id", "task_owner", "task_priority"]
    },
    {
      name               = "gsi_session_index"
      hash_key           = "session_id"
      range_key          = "task_status"
      read_capacity      = var.dynamodb_gsi_index_table_read_capacity
      write_capacity     = var.dynamodb_gsi_index_table_write_capacity
      projection_type    = "INCLUDE"
      non_key_attributes = ["task_id"]
    }
  ]

  autoscaling_read = {
    scale_in_cooldown  = 300
    scale_out_cooldown = 30
    target_value       = 70
    min_capacity       = 10
    max_capacity       = 50
  }

  autoscaling_write = {
    scale_in_cooldown  = 300
    scale_out_cooldown = 30
    target_value       = 70
    min_capacity       = 10
    max_capacity       = 50
  }

  autoscaling_indexes = {
    gsi_ttl_index = {
      read_max_capacity  = 50
      read_min_capacity  = 10
      write_max_capacity = 50
      write_min_capacity = 10
    },
    gsi_session_index = {
      read_max_capacity  = 50
      read_min_capacity  = 10
      write_max_capacity = 50
      write_min_capacity = 10
    }
  }

  tags = {
    service = "htc-aws"
  }
}
