# Copyright 2024 Amazon.com, Inc. or its affiliates.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

variable "region" {
  description = "AWS region"
  type        = string
}

variable "suffix" {
  description = "Resource name suffix (project_name)"
  type        = string
}

variable "lambda_runtime" {
  description = "Python runtime for the controller Lambda"
  type        = string
}

variable "aws_htc_ecr" {
  description = "ECR registry URL (for the SAM build image used by terraform-aws-modules/lambda)"
  type        = string
}

variable "orchestrator_function_name" {
  description = "ORB orchestrator Lambda function name the controller invokes"
  type        = string
}

variable "orchestrator_function_arn" {
  description = "ORB orchestrator Lambda ARN (for the lambda:InvokeFunction grant)"
  type        = string
}

variable "orb_template_id" {
  description = "ORB template id used for scale-up"
  type        = string
  default     = "EC2Fleet-Instant-OnDemand"
}

variable "task_queue_service" {
  description = "Task queue backend service (SQS or PrioritySQS)"
  type        = string
}

variable "task_queue_config" {
  description = "Task queue client config JSON (e.g. priorities count for PrioritySQS)"
  type        = string
}

variable "tasks_queue_name" {
  description = "Name of the (first) SQS task queue read for the backlog"
  type        = string
}

variable "sqs_queue" {
  description = "Base name of the SQS task queue(s); the controller reads ApproximateNumberOfMessages (used as the IAM resource prefix to cover all priority queues)"
  type        = string
}

variable "sqs_kms_key_arn" {
  description = "KMS CMK ARN encrypting the task queue(s) (kms:Decrypt is required to read queue attributes)"
  type        = string
}

variable "error_log_group" {
  description = "Global error CloudWatch log group name (read at import by the shared queue DAL's grid_error_logger)"
  type        = string
}

variable "error_logging_stream" {
  description = "Global error CloudWatch log stream name (read at import by the shared queue DAL's grid_error_logger)"
  type        = string
}

# The controller scales in vCPUs (EC2 Fleet TargetCapacityUnitType=vcpu). desired_pairs =
# ceil(backlog / target_pending_per_pair); desired_vcpus = desired_pairs * pair_cpu, clamped to
# [min_vcpus, max_vcpus]; each instance auto-packs floor(vcpus / pair_cpu) pairs at boot.
variable "pair_cpu" {
  description = "vCPUs per worker pair (converts pairs <-> vCPUs in the controller)"
  type        = number
  default     = 1
}

variable "pair_memory" {
  description = "MiB per worker pair; only used as a fallback to size a machine by memory when ORB status has no vcpus"
  type        = number
  default     = 2048
}

variable "min_vcpus" {
  description = "Minimum total fleet vCPUs (floor of the vCPU target)"
  type        = number
  default     = 0
}

variable "max_vcpus" {
  description = "Maximum total fleet vCPUs (ceiling of the vCPU target)"
  type        = number
  default     = 64
}

variable "target_pending_per_pair" {
  description = "Target pending tasks per worker pair; desired pairs = ceil(backlog / this)"
  type        = number
  default     = 4
}

variable "control_interval" {
  description = "Controller reconcile interval (seconds)"
  type        = number
  default     = 60
}

variable "drain_deadline_sec" {
  description = "Seconds a cordoned worker may finish in-flight work before being force-terminated on graceful scale-down (≈ worker compose stop_grace_period)"
  type        = number
  default     = 1500
}

variable "state_table_name" {
  description = "DynamoDB task state table name (read for the live-task heartbeat busy-worker detection)"
  type        = string
}

variable "state_table_arn" {
  description = "DynamoDB task state table ARN (for the dynamodb:Query grant on the table + its GSIs)"
  type        = string
}

variable "state_table_kms_key_arn" {
  description = "KMS CMK ARN encrypting the state table (kms:Decrypt is required to Query the encrypted table)"
  type        = string
}

variable "state_table_service" {
  description = "State table backend service (DynamoDB)"
  type        = string
  default     = "DynamoDB"
}

variable "state_table_config" {
  description = "State table client config JSON (e.g. retries)"
  type        = string
  default     = "{}"
}

variable "kms_key_admin_arns" {
  description = "IAM principal ARNs allowed to administer the controller CloudWatch logs CMK"
  type        = list(string)
  default     = []
}

variable "kms_deletion_window" {
  description = "KMS key deletion window (days)"
  type        = number
  default     = 7
}
