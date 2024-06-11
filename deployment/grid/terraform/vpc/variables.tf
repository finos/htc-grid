# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "cluster_name" {
  description = "Name of EKS cluster in AWS"
  type        = string
  default     = "htc"
}

variable "public_subnets" {
  description = "IP range for public subnet"
  type        = number
}

variable "private_subnets" {
  description = "IP range for private subnet"
  type        = number
}

variable "vpc_range" {
  description = "IP range for private subnet"
  type        = number
}

variable "enable_private_subnet" {
  description = "enable private subnet"
  type        = bool
  default     = false
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

variable "allowed_access_cidr_blocks" {
  description = "List of CIDR blocks which are allowed ingress/egress access from/to the VPC"
  type        = list(string)
}
