# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

variable "region" {
  description = "AWS region"
  default     = "eu-west-1"
}

variable "cluster_name" {
  description = "Name of EKS cluster in AWS"
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
