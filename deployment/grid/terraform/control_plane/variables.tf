# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

variable "region" {
  description = "AWS region"
}

variable "aws_htc_ecr" {
  description = "URL of Amazon ECR image repostiories"
}

variable "lambda_runtime" {
  description = "Python version"
}

variable "ddb_status_table" {
  description = "HTC DynamoDB table name"
}

variable "sqs_queue" {
  description = "HTC SQS queue name"
}

variable "sqs_dlq" {
  description = "HTC SQS queue dlq name"
}

variable "s3_bucket" {
  description = "S3 bucket name"
}

variable "grid_storage_service" {
  description = "Configuration string for internal results storage system"
}

variable "task_input_passed_via_external_storage" {
  description = "Indicator for passing the args through stdin"
}

variable "lambda_name_ttl_checker" {
  description = "Lambda name for ttl checker"
}

variable "lambda_name_submit_tasks" {
  description = "Lambda name for submit task"
}

variable "lambda_name_cancel_tasks" {
  description = "Lambda name for cancel tasks"
}

variable "lambda_name_get_results" {
  description = "Lambda name for get result task"
}

variable "metrics_are_enabled" {
  description = "If set to True(1) then metrics will be accumulated and delivered downstream for visualisation"
}

variable "metrics_submit_tasks_lambda_connection_string" {
  description = "The type and the connection string for the downstream"
}

variable "metrics_get_results_lambda_connection_string" {
  description = "The type and the connection string for the downstream"
}

variable "metrics_cancel_tasks_lambda_connection_string" {
  description = "The type and the connection string for the downstream"
}

variable "metrics_ttl_checker_lambda_connection_string" {
  description = "The type and the connection string for the downstream"
}

variable "agent_use_congestion_control" {
  description = "Use Congestion Control protocol at pods to avoid overloading DDB"
}

variable "error_log_group" {
  description = "Log group for errors"
}

variable "error_logging_stream" {
  description = "Log stream for errors"
}

variable "dynamodb_table_write_capacity" {
  description = "write capacity for the status table"
}

variable "dynamodb_table_read_capacity" {
  description = "read capacity for the status table"
}


variable "dynamodb_gsi_index_table_write_capacity" {
  description = "write capacity for the status table (gsi index)"
}

variable "dynamodb_gsi_index_table_read_capacity" {
  description = "read capacity for the status table (gsi index)"
}

variable "dynamodb_gsi_ttl_table_write_capacity" {
  description = "write capacity for the status table(gsi ttl)"
}

variable "dynamodb_gsi_ttl_table_read_capacity" {
  description = "read capacity for the status table (gsi ttl)"
}

variable "dynamodb_gsi_parent_table_write_capacity" {
  description = "write capacity for the status table (gsi parent)"
}

variable "dynamodb_gsi_parent_table_read_capacity" {
  description = "read capacity for the status table (gsi parent)"
}

variable "suffix" {
  description = "suffix for generating unique name for AWS resource"
}

variable "vpc_private_subnet_ids" {
  description = "Private subnet IDs"
}

variable "vpc_public_subnet_ids" {
  description = "Public subnet IDs"
}

variable "vpc_default_security_group_id" {
  description = "Default SG ID"
}

variable "vpc_id" {
  description = "Default VPC ID"
}

variable "vpc_cidr" {
  description = "Default VPC CIDR"
}
variable "nlb_influxdb" {
  description = "network load balancer url  in front of influxdb"
  default = ""
}

variable "cognito_userpool_arn" {
  description = "ARN of the user pool used for authentication"
}

variable "cluster_name" {
  description = "ARN of the user pool used for authentication"
}

variable "api_gateway_version" {
  description = "version deployed by API Gateway"
}


