# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

variable "region" {
  description = "AWS region"
}

variable "input_role" {
  description = "Additional IAM roles to add to the aws-auth configmap."
  type = list(object({
    rolearn  = string
    username = string
    groups   = list(string)
  }))
}

variable "kubernetes_version" {
  description = "Name of EKS cluster in AWS"
}

variable "htc_agent_namespace" {
  description = "kubernetes namespace for the deployment of the agent"
  default     = "default"
}

variable "aws_htc_ecr" {
  description = "URL of Amazon ECR image repostiories"
}

variable "cwa_version" {
  description = "CloudWatch Adapter for Kubernetes version"
}

variable "aws_node_termination_handler_version" {
  description = "version of the deployment managing node termination"
}

variable "cw_agent_version" {
  description = "CloudWatch Agent version"
}

variable "fluentbit_version" {
  description = "Fluentbit version"
}

variable "cluster_name" {
  description = "Name of EKS cluster in AWS"
}

variable "k8s_ca_version" {
  description = "Cluster autoscaler version"
}

variable "k8s_keda_version" {
  description = "Keda version"
}

variable "suffix" {
  description = "suffix for generating unique name for AWS resource"
  default     = ""
}

variable "eks_worker_groups" {
  type = any
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

variable "enable_private_subnet" {
  description = "enable private subnet"
  type        = bool
}

variable "grafana_admin_password" {
  description = "Holds the default/initial password that will be used for authenticating with Grafana"
  type        = string
  sensitive   = true
}

variable "kms_deletion_window" {
  description = "Number of days after which KMS key will be permanently deleted"
  default     = 7
}

variable "kms_key_admin_roles" {
  description = "List of roles to assign KMS Key Administrator permissions"
  default     = []
}

# variable "htc_dynamodb_table_arn" {
#   description = "htc_dynamodb_table_arn"
#   type        = string
# }

# variable "sqs_queue_and_dlq_arns" {
#   description = "sqs_queue_and_dlq_arns"
#   type        = list(string)
# }

# variable "control_plane_kms_key_arns" {
#   description = "control_plane_kms_key_arns"
#   type        = list(string)
# }

variable "create_eks_compute_plane" {
  description = "Controls whether the EKS Compute Plane will be deployed as part of the grid"
  default     = true
}

# variable "htc_agent_permissions_policy_arn" {
#   description = "HTC AGent Permissions Policy ARN"
#   type        = string
# }

variable "ecr_pull_through_cache_policy_arn" {
  description = "ECR Pull Through Cache Permissions Policy ARN"
  type        = string
}

variable "node_drainer_lambda_role_arn" {
  description = "Node Drainer Lambda Role ARN"
  type        = string
}
