# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

variable "region" {
  description = "the region where the ECR repository will be created"
  default     = "eu-west-1"
}

variable "aws_htc_ecr" {
  description = "URL of Amazon ECR image repostiories"
  default     = ""
}

variable "image_to_copy" {
  description = "contains the list of third party images to copy (and where to copy them)"
  type        = map(any)
}

variable "repository" {
  description = "contains the list of ECR repository to create"
  type        = list(any)
}

variable "lambda_runtime" {
  description = "runtime used for the custom worker"
  type        = string
  default     = "python3.11"
}

variable "rebuild_runtimes" {
  description = "Enforce a local rebuild of the runtime images"
  type        = string
  default     = "false"
}

variable "kms_deletion_window" {
  description = "Number of days after which KMS key will be permanently deleted"
  default     = 7
}

variable "kms_key_admin_roles" {
  description = "List of roles to assign KMS Key Administrator permissions"
  default     = []
}
