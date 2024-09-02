# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

variable "region" {
  description = "AWS region"
  type        = string
}

variable "aws_htc_ecr" {
  description = "URL of Amazon ECR image repostiories"
  type        = string
}

variable "lambda_runtime" {
  description = "Python version"
  type        = string
  default     = "python3.11"
}

variable "ddb_state_table" {
  description = "HTC DynamoDB table name"
  type        = string
}

variable "dynamodb_autoscaling_enabled" {
  description = "Switches autoscaling for the dynamodb table"
  type        = bool
}

variable "dynamodb_billing_mode" {
  description = "Sets billing mode [PROVISIONED] or [PAY_PER_REQUEST]"
  type        = string
}

variable "sqs_queue" {
  description = "HTC SQS queue name"
  type        = string
}

variable "sqs_dlq" {
  description = "HTC SQS queue dlq name"
  type        = string
}

variable "s3_bucket" {
  description = "S3 bucket name"
  type        = string
}

variable "grid_storage_service" {
  description = "Configuration string for internal results storage system"
  type        = string
}

variable "task_queue_service" {
  description = "Configuration string for the type of queuing service to use"
  type        = string
}

variable "task_queue_config" {
  description = "Dictionary configuration of the tasks queue"
  type        = string
}

variable "task_input_passed_via_external_storage" {
  description = "Indicator for passing the args through stdin"
  type        = number
}

variable "lambda_name_ttl_checker" {
  description = "Lambda name for ttl checker"
  type        = string
}

variable "lambda_name_submit_tasks" {
  description = "Lambda name for submit task"
  type        = string
}

variable "lambda_name_cancel_tasks" {
  description = "Lambda name for cancel tasks"
  type        = string
}

variable "lambda_name_get_results" {
  description = "Lambda name for get result task"
  type        = string
}

variable "lambda_name_scaling_metrics" {
  description = "Lambda function name for scaling_metrics"
  type        = string
}

variable "lambda_name_node_drainer" {
  description = "Lambda function name for node_drainer"
  type        = string
}

variable "metrics_are_enabled" {
  description = "If set to True(1) then metrics will be accumulated and delivered downstream for visualisation"
  type        = number
}

variable "metrics_submit_tasks_lambda_connection_string" {
  description = "The type and the connection string for the downstream"
  type        = string
}

variable "metrics_get_results_lambda_connection_string" {
  description = "The type and the connection string for the downstream"
  type        = string
}

variable "metrics_cancel_tasks_lambda_connection_string" {
  description = "The type and the connection string for the downstream"
  type        = string
}

variable "metrics_ttl_checker_lambda_connection_string" {
  description = "The type and the connection string for the downstream"
  type        = string
}

# variable "agent_use_congestion_control" {
#   description = "Use Congestion Control protocol at pods to avoid overloading DDB"
#   type        = bool
# }

variable "error_log_group" {
  description = "Log group for errors"
  type        = string
}

variable "error_logging_stream" {
  description = "Log stream for errors"
  type        = string
}

variable "dynamodb_table_write_capacity" {
  description = "write capacity for the status table"
  type        = number
}

variable "dynamodb_table_read_capacity" {
  description = "read capacity for the status table"
  type        = number
}

variable "dynamodb_gsi_index_table_write_capacity" {
  description = "write capacity for the status table (gsi index)"
  type        = number
}

variable "dynamodb_gsi_index_table_read_capacity" {
  description = "read capacity for the status table (gsi index)"
  type        = number
}

variable "dynamodb_gsi_ttl_table_write_capacity" {
  description = "write capacity for the status table(gsi ttl)"
  type        = number
}

variable "dynamodb_gsi_ttl_table_read_capacity" {
  description = "read capacity for the status table (gsi ttl)"
  type        = number
}

# variable "dynamodb_gsi_parent_table_write_capacity" {
#   description = "write capacity for the status table (gsi parent)"
#   type        = number
# }

# variable "dynamodb_gsi_parent_table_read_capacity" {
#   description = "read capacity for the status table (gsi parent)"
#   type        = number
# }

variable "suffix" {
  description = "suffix for generating unique name for AWS resource"
  type        = string
}

variable "vpc_private_subnet_ids" {
  description = "Private subnet IDs"
  type        = list(string)
}

# variable "vpc_public_subnet_ids" {
#   description = "Public subnet IDs"
#   type        = string
# }

variable "vpc_default_security_group_id" {
  description = "Default SG ID"
  type        = string
}

variable "vpc_id" {
  description = "Default VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "Default VPC CIDR"
  type        = string
}

variable "nlb_influxdb" {
  description = "network load balancer url  in front of influxdb"
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "Name of EKS cluster in AWS"
  type        = string
}

variable "api_gateway_version" {
  description = "version deployed by API Gateway"
  type        = string
}

variable "state_table_service" {
  description = "State Table service type"
  type        = string
}

variable "state_table_config" {
  description = "Status Table configuration"
  type        = string
}

variable "priorities" {
  type = map(number)
  default = {
    "__0" = 0
  }
}

variable "kms_key_admin_roles" {
  description = "List of roles to assign KMS Key Administrator permissions"
  type        = list(string)
  default     = []
}

variable "kms_deletion_window" {
  description = "Number of days after which KMS key will be permanently deleted"
  type        = number
  default     = 7
}

variable "namespace_metrics" {
  description = "NameSpace for metrics"
  type        = string
}

variable "tasks_queue_name" {
  description = "HTC queue name"
  type        = string
}

variable "dimension_name_metrics" {
  description = "Dimensions name/value for the CloudWatch metrics"
  type        = string
}

variable "period_metrics" {
  description = "Period for metrics in minutes"
  type        = number
}

variable "metric_name" {
  description = "Metrics name"
  type        = string
}

variable "metrics_event_rule_time" {
  description = "Fires event rule to put metrics"
  type        = string
}

variable "graceful_termination_delay" {
  description = "graceful termination delay for scaled in action"
  type        = number
}

# variable "aws_xray_daemon_version" {
#   description = "version for the XRay daemon"
#   type        = string
# }

variable "eks_managed_node_groups" {
  description = "Map of names and ARNs of EKS Managed Node Group ASGs"
  type        = map(map(string))
}

variable "lambda_configuration_s3_source" {
  description = "The Lambda Layer S3 bucket source"
  type        = string
}

variable "lambda_configuration_s3_source_kms_key_arn" {
  description = "The CMK KMS Key ARN for the Lambda Layer S3 bucket source"
  type        = string
}

variable "allowed_access_cidr_blocks" {
  description = "List of CIDR blocks which are allowed ingress/egress access from/to the VPC"
  type        = list(string)
}
