# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


locals {
  account_id           = data.aws_caller_identity.current.account_id
  dns_suffix           = data.aws_partition.current.dns_suffix
  partition            = data.aws_partition.current.partition
  aws_htc_ecr          = var.aws_htc_ecr != "" ? var.aws_htc_ecr : "${local.account_id}.dkr.ecr.${var.region}.${local.dns_suffix}"
  lambda_build_runtime = "${local.aws_htc_ecr}/ecr-public/sam/build-${var.lambda_runtime}:1"

  default_kms_key_admin_arns = [
    data.aws_caller_identity.current.arn,
    "arn:${local.partition}:iam::${local.account_id}:root"
  ]
  additional_kms_key_admin_role_arns = [for k, v in data.aws_iam_role.additional_kms_key_admin_roles : v.arn]
  kms_key_admin_arns                 = concat(local.default_kms_key_admin_arns, local.additional_kms_key_admin_role_arns)
}


data "aws_iam_role" "additional_kms_key_admin_roles" {
  for_each = toset(var.kms_key_admin_roles)

  name = each.key
}


# Retrieve the account ID
data "aws_caller_identity" "current" {}


# Retrieve AWS Partition
data "aws_partition" "current" {}
