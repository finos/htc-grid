# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


locals {
  account_id            = data.aws_caller_identity.current.account_id
  dns_suffix            = data.aws_partition.current.dns_suffix
  partition             = data.aws_partition.current.partition
  private_subnet_range  = var.vpc_range - (32 - var.private_subnets)
  public_subnet_range   = var.vpc_range - (32 - var.public_subnets)
  private_subnet_ranges = [for cidr_block in data.aws_availability_zones.available.names : local.private_subnet_range]
  public_subnet_ranges  = [for cidr_block in data.aws_availability_zones.available.names : local.public_subnet_range]
  //public_subnets_size = ceil(log(length(data.aws_availability_zones.available) * pow(2, local.public_subnet_range),2))
  //private_subnets_size = ceil(log(3 * pow(2,local.private_subnet_range),2))
  //subnets = cidrsubnets("10.0.0.0/16",local.private_subnets_size,local.public_subnets_size)
  subnets         = cidrsubnets("10.0.0.0/16", concat(local.public_subnet_ranges, local.private_subnet_ranges)...)
  public_subnets  = slice(local.subnets, 0, length(data.aws_availability_zones.available.names))
  private_subnets = slice(local.subnets, length(data.aws_availability_zones.available.names), 2 * length(data.aws_availability_zones.available.names))

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


data "aws_availability_zones" "available" {
  state = "available"
}


# Retrieve the account ID
data "aws_caller_identity" "current" {}


# Retrieve AWS Partition
data "aws_partition" "current" {}
