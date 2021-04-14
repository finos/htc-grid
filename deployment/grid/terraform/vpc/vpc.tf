# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

data "aws_availability_zones" "available" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.77.0"
  name                 = "${var.cluster_name}-vpc"
  cidr                 = "10.0.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  #private_subnets      = ["10.0.0.0/20","10.0.32.0/20", "10.0.64.0/20"]
  #public_subnets       = ["10.0.130.0/24", "10.0.131.0/24", "10.0.132.0/24"]
  private_subnets      = var.private_subnets
  public_subnets       = var.public_subnets
  enable_nat_gateway   = !var.enable_private_subnet
  single_nat_gateway   = !var.enable_private_subnet
  # required for private endpoint
  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_sqs_endpoint              = var.enable_private_subnet
  sqs_endpoint_private_dns_enabled = var.enable_private_subnet
  sqs_endpoint_security_group_ids  = var.enable_private_subnet == true ? [module.vpc.default_security_group_id] : []

  enable_s3_endpoint               = var.enable_private_subnet
  enable_dynamodb_endpoint         = var.enable_private_subnet

  enable_ec2_autoscaling_endpoint = var.enable_private_subnet
  ec2_autoscaling_endpoint_private_dns_enabled = var.enable_private_subnet
  ec2_autoscaling_endpoint_security_group_ids = var.enable_private_subnet == true ? [module.vpc.default_security_group_id] : []
  ec2_autoscaling_endpoint_subnet_ids = var.enable_private_subnet == true ? module.vpc.private_subnets : []

  enable_ec2_endpoint = var.enable_private_subnet
  ec2_endpoint_private_dns_enabled = var.enable_private_subnet
  ec2_endpoint_security_group_ids = var.enable_private_subnet == true ? [module.vpc.default_security_group_id] : []
  ec2_endpoint_subnet_ids = var.enable_private_subnet == true ? module.vpc.private_subnets : []

  enable_ecr_dkr_endpoint = var.enable_private_subnet
  ecr_dkr_endpoint_private_dns_enabled = var.enable_private_subnet
  ecr_dkr_endpoint_security_group_ids = var.enable_private_subnet == true ? [module.vpc.default_security_group_id] : []
  ecr_dkr_endpoint_subnet_ids = var.enable_private_subnet == true ? module.vpc.private_subnets : []

  enable_ecr_api_endpoint = var.enable_private_subnet
  ecr_api_endpoint_private_dns_enabled = var.enable_private_subnet
  ecr_api_endpoint_security_group_ids = var.enable_private_subnet == true ? [module.vpc.default_security_group_id] : []
  ecr_api_endpoint_subnet_ids = var.enable_private_subnet == true ? module.vpc.private_subnets : []

  enable_monitoring_endpoint = var.enable_private_subnet
  monitoring_endpoint_private_dns_enabled = var.enable_private_subnet
  monitoring_endpoint_security_group_ids = var.enable_private_subnet == true ? [module.vpc.default_security_group_id] : []
  monitoring_endpoint_subnet_ids = var.enable_private_subnet == true ? module.vpc.private_subnets : []

  enable_logs_endpoint = var.enable_private_subnet
  logs_endpoint_private_dns_enabled = var.enable_private_subnet
  logs_endpoint_security_group_ids = var.enable_private_subnet == true ? [module.vpc.default_security_group_id] : []
  logs_endpoint_subnet_ids = var.enable_private_subnet == true ? module.vpc.private_subnets : []

  enable_elasticloadbalancing_endpoint = var.enable_private_subnet
  elasticloadbalancing_endpoint_private_dns_enabled = var.enable_private_subnet
  elasticloadbalancing_endpoint_security_group_ids = var.enable_private_subnet == true ? [module.vpc.default_security_group_id] : []
  elasticloadbalancing_endpoint_subnet_ids = var.enable_private_subnet == true ? module.vpc.private_subnets : []

  enable_apigw_endpoint = true
  apigw_endpoint_private_dns_enabled = true
  apigw_endpoint_security_group_ids =  [module.vpc.default_security_group_id]
  apigw_endpoint_subnet_ids =  module.vpc.private_subnets


  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }

}

data "aws_vpc" "selected" {
  id = module.vpc.vpc_id
}

resource "aws_security_group_rule" "https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [data.aws_vpc.selected.cidr_block]
  security_group_id = module.vpc.default_security_group_id
}
