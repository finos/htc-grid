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

variable "cluster_name" {
  description = "Grid cluster name (used for the worker log group path)"
  type        = string
}

variable "aws_htc_ecr" {
  description = "ECR registry URL hosting the agent/rie/get-layer images"
  type        = string
}

variable "vpc_id" {
  description = "VPC the worker instances run in"
  type        = string
}

variable "vpc_private_subnet_ids" {
  description = "Private subnets for worker instances"
  type        = list(string)
}

variable "htc_agent_permissions_policy_arn" {
  description = "Control-plane IAM policy granting SQS/DDB/S3/CloudWatch/KMS — attached to the instance profile"
  type        = string
}

variable "ssm_config_parameter_arn" {
  description = "ARN of the SSM SecureString holding Agent_config.tfvars.json"
  type        = string
}

variable "ssm_config_parameter_name" {
  description = "Name of the SSM SecureString holding the agent config"
  type        = string
}

variable "ssm_config_kms_key_arn" {
  description = "KMS key ARN that encrypts the SSM config parameter (for kms:Decrypt)"
  type        = string
}

variable "lambda_configuration_s3_source" {
  description = "S3 URI of the Lambda code zip (s3://bucket/lambda.zip) the get-layer init downloads"
  type        = string
}

variable "kms_key_admin_arns" {
  description = "IAM principal ARNs allowed to administer the worker log-group CMK"
  type        = list(string)
  default     = []
}

variable "handler" {
  description = "Lambda handler arg passed to the RIE (file.function)"
  type        = string
  default     = "bootstrap.main"
}

variable "lambda_function_name" {
  description = "Function name the agent invokes on the RIE. The AWS Lambda RIE only serves the literal 'function'."
  type        = string
  default     = "function"
}

variable "pair_cpu" {
  description = "vCPU budget per pair for NUM_PAIRS auto-compute"
  type        = number
  default     = 1
}

variable "pair_memory" {
  description = "Memory (MB) budget per pair for NUM_PAIRS auto-compute"
  type        = number
  default     = 2048
}

# Per-container hard limits — sourced from the SAME agent_configuration block the EKS
# (htc-agent) backend uses, so resources are defined in ONE place. Units match the chart:
# CPU in millicores, memory in MiB. Rendered into the compose services' cpus/mem_limit.
variable "agent_max_cpu" {
  description = "Agent container CPU limit (millicores) — from agent_configuration.agent.maxCPU"
  type        = number
  default     = 50
}

variable "agent_max_memory" {
  description = "Agent container memory limit (MiB) — from agent_configuration.agent.maxMemory"
  type        = number
  default     = 100
}

variable "lambda_max_cpu" {
  description = "RIE container CPU limit (millicores) — from agent_configuration.lambda.maxCPU"
  type        = number
  default     = 900
}

variable "lambda_max_memory" {
  description = "RIE container memory limit (MiB) — from agent_configuration.lambda.maxMemory"
  type        = number
  default     = 3900
}

variable "compose_plugin_s3_uri" {
  description = "S3 URI of the staged docker-compose plugin binary"
  type        = string
}

variable "image_tag" {
  description = "Image tag for awshpc-lambda / lambda-init (usually project_name); RIE uses 'provided'"
  type        = string
}
