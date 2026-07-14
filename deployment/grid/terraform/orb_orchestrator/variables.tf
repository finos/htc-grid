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

variable "aws_htc_ecr" {
  description = "ECR registry URL (for the SAM build image used by terraform-aws-modules/lambda)"
  type        = string
}

variable "lambda_runtime" {
  description = "Python runtime for the ORB orchestrator Lambda (zip build)"
  type        = string
  default     = "python3.11"
}

variable "table_prefix" {
  description = "DynamoDB table prefix for ORB state; must match the bundled ORB config"
  type        = string
}

variable "worker_instance_role_arn" {
  description = "Worker instance role ARN; the orchestrator gets iam:PassRole on it (workers attach an instance profile)"
  type        = string
}

variable "worker_instance_profile_arn" {
  description = "Worker instance profile ARN ORB attaches to launched instances"
  type        = string
}

variable "worker_subnet_ids" {
  description = "Private subnet ids ORB launches workers into"
  type        = list(string)
}

variable "worker_security_group_id" {
  description = "Worker security group id"
  type        = string
}

variable "worker_ami_id" {
  description = "AL2023 AMI id for workers"
  type        = string
}

variable "orb_template_id" {
  description = "Which prebuilt template (from config/aws_templates.json) to grid-complete and use for worker launches. EC2Fleet-Instant-ABIS is currently unusable (orb-py's _validate_prerequisites rejects ABIS-only templates); use the enumerated EC2Fleet-Instant-OnDemand."
  type        = string
  default     = "EC2Fleet-Instant-OnDemand"
}

variable "worker_user_data_plain" {
  description = "Plain-text worker cloud-init, baked into the rendered ORB template's user_data at deploy time (ORB base64-encodes it itself)"
  type        = string
  sensitive   = true
}

variable "pair_cpu" {
  description = "vCPUs per worker pair; the fleet target capacity is sized in vCPUs and each instance auto-packs floor(vCPU/pair_cpu) pairs"
  type        = number
}

variable "pair_memory" {
  description = "MiB per worker pair (paired with pair_cpu for the boot-time auto-pack; used for the ABIS min-memory floor guard)"
  type        = number
}

variable "max_instances" {
  description = "ORB per-template max_instances cap (upper bound on the fleet); overrides the selected template's value"
  type        = number
  default     = 10
}

variable "kms_key_admin_arns" {
  description = "IAM principal ARNs allowed to administer the ORB state CMK"
  type        = list(string)
  default     = []
}

variable "kms_deletion_window" {
  description = "KMS key deletion window (days)"
  type        = number
  default     = 7
}
