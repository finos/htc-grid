# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

variable "region" {
  default     = "eu-west-1"
  description = "AWS region"
}


variable "cluster_name" {
  default = "htc"
  description = "Name of EKS cluster in AWS"
}


variable "public_subnets" {
  description = "list of CIDR blocks for public subnet"
  type = list(string)
  default = []
}

variable "private_subnets" {
  description = "list of CIDR blocks for private subnet"
  type = list(string)
  default = []
}


variable "enable_private_subnet" {
  description = "enable private subnet"
  type = bool
  default = false
}
