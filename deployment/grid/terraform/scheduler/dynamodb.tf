# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/
 
resource "aws_dynamodb_table" "htc_tasks_status_table" {
  name           = var.ddb_status_table
  read_capacity  = var.dynamodb_table_read_capacity
  write_capacity = var.dynamodb_table_write_capacity
  
  hash_key       = "task_id"


  attribute {
    name = "session_id"
    type = "S"
  }

  attribute {
    name = "task_id"
    type = "S"
  }

  # attribute {
  #   name = "submission_timestamp"
  #   type = "N"
  # }

  # attribute {
  #   name = "task_completion_timestamp"
  #   type = "N"
  # }

  attribute {
    name = "task_status"
    type = "S"
  }

  # attribute {
  #   name = "task_owner"
  #   type = "S"
  # }
  # default value "None"

  # attribute {
  #   name = "retries"
  #   type = "N"
  # }

  # attribute {
  #   name = "task_definition"
  #   type = "S"
  # }

  # attribute {
  #   name = "sqs_handler_id"
  #   type = "S"
  # }

  attribute {
    name = "heartbeat_expiration_timestamp"
    type = "N"
  }

  # attribute {
  #   name = "parent_session_id"
  #   type = "S"
  # }
  
  global_secondary_index {
    name               = "gsi_ttl_index"
    hash_key           = "task_status"
    range_key          = "heartbeat_expiration_timestamp"
    read_capacity      = var.dynamodb_gsi_ttl_table_read_capacity
    write_capacity     = var.dynamodb_gsi_ttl_table_write_capacity
    projection_type    = "INCLUDE"
    non_key_attributes = ["task_id", "task_owner"]
  }

  global_secondary_index {
    name               = "gsi_session_index"
    hash_key           = "session_id"
    range_key          = "task_status"
    read_capacity      = var.dynamodb_gsi_index_table_read_capacity
    write_capacity     = var.dynamodb_gsi_index_table_write_capacity
    projection_type    = "INCLUDE"
    non_key_attributes = ["task_id"]
  }

  # global_secondary_index {
  #   name               = "gsi_parent_session_index"
  #   hash_key           = "parent_session_id"
  #   range_key          = "session_id"
  #   read_capacity      = var.dynamodb_gsi_parent_table_read_capacity
  #   write_capacity     = var.dynamodb_gsi_parent_table_write_capacity
  #   projection_type    = "INCLUDE"
  #   non_key_attributes = ["task_id", "task_status"]
  # }


  tags = {
    service     = "htc-aws"
  }
}