# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

module "dynamodb_table" {
  source = "terraform-aws-modules/dynamodb-table/aws"
  version = "3.1.2"
  name   = var.ddb_state_table

  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_table_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_table_write_capacity : null

  autoscaling_enabled = var.dynamodb_autoscaling_enabled

  billing_mode = var.dynamodb_billing_mode

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

    #  {
    #   name = "submission_timestamp"
    #   type = "N"
    # }

    #  {
    #   name = "task_completion_timestamp"
    #   type = "N"
    # }

    {
      name = "task_status"
      type = "S"
    },



    #  {
    #   name = "task_owner"
    #   type = "S"
    # }
    # default value "None"

    #  {
    #   name = "retries"
    #   type = "N"
    # }

    #  {
    #   name = "task_definition"
    #   type = "S"
    # }

    #  {
    #   name = "sqs_handler_id"
    #   type = "S"
    # }

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