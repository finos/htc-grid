# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

variable "region" {
  description = "AWS region"
  default     = "eu-west-1"
}

variable "input_role" {
  description = "Additional IAM roles to add to the aws-auth configmap."
  type = list(object({
    rolearn  = string
    username = string
    groups   = list(string)
  }))
  default = []
}

variable "cluster_name" {
  description = "Name of EKS cluster in AWS"
  default     = "htc"
}

variable "config_name" {
  description = "Default path for the SSM parameter storing the configuration of the grid"
  default     = "htc"
}

variable "lambda_runtime" {
  description = "Lambda runtine"
  default     = "python3.11"
}

variable "kubernetes_version" {
  description = "Name of EKS cluster in AWS"
  default     = "1.25"
}

variable "k8s_ca_version" {
  description = "Cluster autoscaler version"
  default     = "v1.21.0"
}

variable "k8s_keda_version" {
  description = "Keda version"
  default     = "2.11.2"
}

variable "aws_htc_ecr" {
  description = "URL of Amazon ECR image repostiories"
  default     = ""
}

variable "cwa_version" {
  description = "Cloud Watch Adapter for kubernetes version"
  default     = "v0.8.0"
}

variable "aws_node_termination_handler" {
  description = "version of the deployment managing node termination"
  default     = "v1.10.0"
}

variable "cw_agent_version" {
  description = "CloudWatch Agent version"
  default     = "1.247347.5b250583"
}

variable "fluentbit_version" {
  description = "Fluentbit version"
  default     = "2.10.0"
}

variable "ddb_state_table" {
  description = "htc DinamoDB state table name"
  default     = "htc_tasks_state_table"
}

variable "dynamodb_autoscaling_enabled" {
  description = "Switches autoscaling for the dynamodb table"
  type        = bool
  default     = false
}

variable "dynamodb_billing_mode" {
  description = "Sets billing mode [PROVISIONED] or [PAY_PER_REQUEST]"
  default     = "PROVISIONED"
}

variable "task_queue_service" {
  description = "Configuration string for the type of queuing service to be used"
  default     = "SQS"
}

variable "task_queue_config" {
  description = "dictionary queue config"
  default     = "{'priorities':3}"
}

variable "sqs_queue" {
  description = "htc SQS queue name"
  default     = "htc_task_queue"
}

variable "sqs_dlq" {
  description = "htc SQS queue dlq name"
  default     = "htc_task_queue_dlq"
}

variable "s3_bucket" {
  description = "S3 bucket name"
  default     = "htc-stdout-bucket"
}

variable "grid_storage_service" {
  description = "Configuration string for internal results storage system"
  default     = "S3 htc-stdout-bucket-1"
}

variable "state_table_service" {
  description = "State Table service type"
  default     = "DynamoDB"
}

variable "state_table_config" {
  description = "Status Table configuration"
  default     = "{'retries':{'max_attempts':10, 'mode':'adaptive'}}"
}

variable "lambda_name_ttl_checker" {
  description = "Lambda name for ttl checker"
  default     = "ttl_checker"
}

variable "lambda_name_submit_tasks" {
  description = "Lambda name for submit task"
  default     = "submit_task"
}

variable "lambda_name_get_results" {
  description = "Lambda name for get result task"
  default     = "get_results"
}

variable "lambda_name_cancel_tasks" {
  description = "Lambda name for cancel tasks"
  default     = "cancel_tasks"
}

variable "lambda_alb_name" {
  description = "Name of the load balancer for Lambdas"
  default     = "lambda-frontend"
}

variable "metrics_are_enabled" {
  description = "If set to True(1) then metrics will be accumulated and delivered downstream for visualisation"
  default     = "1"
}

variable "metrics_submit_tasks_lambda_connection_string" {
  description = "The type and the connection string for the downstream"
  default     = "influxdb 8086 measurementsdb submit_tasks"
}

variable "metrics_cancel_tasks_lambda_connection_string" {
  description = "The type and the connection string for the downstream"
  default     = "influxdb 8086 measurementsdb cancel_tasks"
}

variable "metrics_get_results_lambda_connection_string" {
  description = "The type and the connection string for the downstream"
  default     = "influxdb 8086 measurementsdb get_results"
}

variable "metrics_ttl_checker_lambda_connection_string" {
  description = "The type and the connection string for the downstream"
  default     = "influxdb 8086 measurementsdb ttl_checker"
}

variable "agent_use_congestion_control" {
  description = "Use Congestion Control protocol at pods to avoid overloading DDB"
  default     = "0"
}

variable "error_log_group" {
  description = "Log group for errors"
  default     = "grid_errors"
}

variable "error_logging_stream" {
  description = "Log stream for errors"
  default     = "lambda_errors"
}

variable "dynamodb_default_read_capacity" {
  description = "default read capacity  for all tables"
  default     = 100
}

variable "dynamodb_default_write_capacity" {
  description = "default write capacity for all tables"
  default     = 100
}

variable "namespace_metrics" {
  description = "NameSpace for metrics"
  default     = "CloudGrid/HTC/Scaling/"
}

variable "dimension_name_metrics" {
  description = "Dimensions name/value for the CloudWatch metrics"
  default     = "cluster_name"
}

variable "htc_path_logs" {
  description = "Path to fluentD to search de logs application"
  default     = "logs/"
}

variable "lambda_name_scaling_metric" {
  description = "Lambda function name for metrics"
  default     = "lambda_scaling_metrics"
}

variable "period_metrics" {
  description = "Period for metrics in minutes"
  default     = "1"
}

variable "metrics_name" {
  description = "Metrics name"
  default     = "pending_tasks_ddb"
}

variable "average_period" {
  description = "Average period in second used by the HPA to compute the current load on the system"
  default     = 30
}

variable "metrics_event_rule_time" {
  description = "Fires event rule to put metrics"
  default     = "rate(1 minute)"
}

variable "htc_agent_name" {
  description = "name of the htc agent to scale out/in"
  default     = "htc-agent"
}

variable "htc_agent_namespace" {
  description = "kubernetes namespace for the deployment of the agent"
  default     = "default"
}

variable "suffix" {
  description = "suffix for generating unique name for AWS resource"
  default     = ""
}

variable "eks_worker_groups" {
  type    = any
  default = []
}

variable "max_htc_agents" {
  description = "maximum number of agents that can run on EKS"
  default     = 100
}

variable "min_htc_agents" {
  description = "minimum number of agents that can run on EKS"
  default     = 1
}

variable "htc_agent_target_value" {
  description = "target value for the load on the system"
  default     = 2
}

variable "graceful_termination_delay" {
  description = "graceful termination delay in second for scaled in action"
  default     = 30
}

variable "empty_task_queue_backoff_timeout_sec" {
  description = "agent backoff timeout in second"
  default     = 0.5
}

variable "work_proc_status_pull_interval_sec" {
  description = "agent pulling interval"
  default     = 0.5
}

variable "task_ttl_expiration_offset_sec" {
  description = "agent TTL for task to time out in second"
  default     = 30
}

variable "task_ttl_refresh_interval_sec" {
  description = "reset interval for agent TTL"
  default     = 5.0
}

variable "dynamodb_results_pull_interval_sec" {
  description = "agent pulling interval for pending task in DDB"
  default     = 0.5
}

variable "agent_task_visibility_timeout_sec" {
  description = "default visibility timeout for SQS messages"
  default     = 3600
}

variable "task_input_passed_via_external_storage" {
  description = "Indicator for passing the args through stdin"
  default     = 1
}

variable "metrics_pre_agent_connection_string" {
  description = "pre agent connection string for monitoring"
  default     = "influxdb 8086 measurementsdb agent_pre"
}

variable "metrics_post_agent_connection_string" {
  description = "post agent connection string for monitoring"
  default     = "influxdb 8086 measurementsdb agent_post"
}

variable "agent_configuration_filename" {
  description = "filename were agent configuration (in json) is going to be stored"
  default     = "Agent_config.json"
}

variable "api_gateway_version" {
  description = "version deployed by API Gateway"
  type        = string
  default     = "v1"
}

variable "enable_xray" {
  description = "Enable XRAY at the agent level"
  type        = number
  default     = 0
}

variable "aws_xray_daemon_version" {
  description = "version for the XRay daemon"
  type        = string
  default     = "latest"
}

variable "enable_private_subnet" {
  description = "enable private subnet"
  type        = bool
  default     = false
}

variable "agent_configuration" {
  description = "Additional IAM roles to add to the aws-auth configmap."
  type        = any
  default     = {}
}

variable "grafana_admin_password" {
  description = "Holds the default/initial password that will be used for authenticating with Grafana"
  type        = string
  default     = ""
  sensitive   = true
}

variable "vpc_cidr_block_public" {
  description = "netmask for the cidr for each public subnet"
  type        = string
  default     = 24
}

variable "vpc_cidr_block_private" {
  description = "netmask for the cidr for each private subnet"
  type        = string
  default     = 24
}

variable "project_name" {
  description = "name of project"
  type        = string
  default     = ""
}
