# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

variable "region" {
  description = "AWS region"
  type        = string
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
  type        = string
}

variable "aws_htc_ecr" {
  description = "URL of Amazon ECR image repostiories"
  type        = string
}

variable "cluster_name" {
  description = "Name of EKS cluster in AWS"
  type        = string
}

variable "k8s_ca_version" {
  description = "Cluster autoscaler version"
  type        = string
}

variable "k8s_keda_version" {
  description = "Keda version"
  type        = string
}

variable "suffix" {
  description = "suffix for generating unique name for AWS resource"
  type        = string
  default     = ""
}

variable "eks_worker_groups" {
  type = any
}

variable "vpc_private_subnet_ids" {
  description = "Private subnet IDs"
  type        = list(string)
}

variable "vpc_public_subnet_ids" {
  description = "Public subnet IDs"
  type        = list(string)
}

variable "vpc_id" {
  description = "Default VPC ID"
  type        = string
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
  type        = number
  default     = 7
}

variable "kms_key_admin_roles" {
  description = "List of roles to assign KMS Key Administrator permissions"
  type        = list(string)
  default     = []
}

variable "ecr_pull_through_cache_policy_arn" {
  description = "ECR Pull Through Cache Permissions Policy ARN"
  type        = string
}

variable "node_drainer_lambda_role_arn" {
  description = "Node Drainer Lambda Role ARN"
  type        = string
}

# variable "allowed_access_cidr_blocks" {
#   description = "List of CIDR blocks which are allowed ingress/egress access from/to the VPC"
#   type        = list(string)
# }

variable "cognito_domain_name" {
  description = "Cognito Domain Name"
  type        = string
}

variable "cognito_userpool_arn" {
  description = "Cognito User Pool ARN"
  type        = string
}

variable "cognito_userpool_id" {
  description = "Cognito User Pool ID"
  type        = string
}

variable "eks_node_volume_size" {
  description = "Size in GB for EKS Worker Nodes"
  type        = number
  default     = 50
}
