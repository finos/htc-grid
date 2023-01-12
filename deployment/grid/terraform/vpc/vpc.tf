# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  private_subnet_range = var.vpc_range - (32 - var.private_subnets)
  public_subnet_range= var.vpc_range - (32 - var.public_subnets)
  private_subnet_ranges = [for cidr_block in data.aws_availability_zones.available.names : local.private_subnet_range]
  public_subnet_ranges = [for cidr_block in data.aws_availability_zones.available.names : local.public_subnet_range]
  //public_subnets_size = ceil(log(length(data.aws_availability_zones.available) * pow(2, local.public_subnet_range),2))
  //private_subnets_size = ceil(log(3 * pow(2,local.private_subnet_range),2))
  //subnets = cidrsubnets("10.0.0.0/16",local.private_subnets_size,local.public_subnets_size)
  subnets = cidrsubnets("10.0.0.0/16",concat(local.public_subnet_ranges,local.private_subnet_ranges)...)
  public_subnets = slice(local.subnets,0,length(data.aws_availability_zones.available.names))
  private_subnets = slice(local.subnets,length(data.aws_availability_zones.available.names),2*length(data.aws_availability_zones.available.names))
}


module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "3.18.1"
  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"
  azs = data.aws_availability_zones.available.names
  private_subnets = local.private_subnets
  public_subnets = local.public_subnets
  enable_nat_gateway = !var.enable_private_subnet
  single_nat_gateway = !var.enable_private_subnet
  # required for private endpoint
  enable_dns_hostnames = true
  enable_dns_support = true
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

module "vpc_endpoints" {
  source = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  vpc_id             = module.vpc.vpc_id
  security_group_ids = [module.vpc.default_security_group_id]
  create = true
  endpoints = {
    sts = {
      service = "sts"
      private_dns_enabled = var.enable_private_subnet
      subnet_ids = var.enable_private_subnet == true ? module.vpc.private_subnets : []
      security_group_ids = var.enable_private_subnet == true ? [module.vpc.default_security_group_id] : []
    }
    sqs = {
      service = "sqs"
      private_dns_enabled = var.enable_private_subnet
      subnet_ids = var.enable_private_subnet == true ? module.vpc.private_subnets : []
      security_group_ids = var.enable_private_subnet == true ? [module.vpc.default_security_group_id] : []
    }
    s3 = {
      service = "s3"
      service_type    = "Gateway"
      route_table_ids = flatten([module.vpc.intra_route_table_ids, module.vpc.private_route_table_ids, module.vpc.public_route_table_ids])
    }
    dynamodb = {
      service = "dynamodb"
      service_type    = "Gateway"
      route_table_ids = flatten([module.vpc.intra_route_table_ids, module.vpc.private_route_table_ids, module.vpc.public_route_table_ids])
    }
    ec2_autoscaling = {
      service = "autoscaling"
      private_dns_enabled = var.enable_private_subnet
      subnet_ids = var.enable_private_subnet == true ? module.vpc.private_subnets : []
      security_group_ids = var.enable_private_subnet == true ? [module.vpc.default_security_group_id] : []
    }
    ec2 = {
      service = "ec2"
      private_dns_enabled = var.enable_private_subnet
      subnet_ids = var.enable_private_subnet == true ? module.vpc.private_subnets : []
      security_group_ids = var.enable_private_subnet == true ? [module.vpc.default_security_group_id] : []
    }
    ecr_dkr = {
      service = "ecr.dkr"
      private_dns_enabled = var.enable_private_subnet
      subnet_ids = var.enable_private_subnet == true ? module.vpc.private_subnets : []
      security_group_ids = var.enable_private_subnet == true ? [module.vpc.default_security_group_id] : []
    }
    ecr_api = {
      service = "ecr.api"
      private_dns_enabled = var.enable_private_subnet
      subnet_ids = var.enable_private_subnet == true ? module.vpc.private_subnets : []
      security_group_ids = var.enable_private_subnet == true ? [module.vpc.default_security_group_id] : []
    }
    monitoring = {
      service = "monitoring"
      private_dns_enabled = var.enable_private_subnet
      subnet_ids = var.enable_private_subnet == true ? module.vpc.private_subnets : []
      security_group_ids = var.enable_private_subnet == true ? [module.vpc.default_security_group_id] : []
    }
    logs = {
      service = "logs"
      private_dns_enabled = var.enable_private_subnet
      subnet_ids = var.enable_private_subnet == true ? module.vpc.private_subnets : []
      security_group_ids = var.enable_private_subnet == true ? [module.vpc.default_security_group_id] : []
    }

    elasticloadbalancing = {
      service = "elasticloadbalancing"
      private_dns_enabled = var.enable_private_subnet
      subnet_ids = var.enable_private_subnet == true ? module.vpc.private_subnets : []
      security_group_ids = var.enable_private_subnet == true ? [module.vpc.default_security_group_id] : []
    }

    api_gateway = {
      service = "execute-api"
      private_dns_enabled = var.enable_private_subnet
      subnet_ids = var.enable_private_subnet == true ? module.vpc.private_subnets : []
      security_group_ids = var.enable_private_subnet == true ? [module.vpc.default_security_group_id] : []
    }

    ssm = {
      service = "ssm"
      private_dns_enabled = var.enable_private_subnet
      subnet_ids = var.enable_private_subnet == true ? module.vpc.private_subnets : []
      security_group_ids = var.enable_private_subnet == true ? [module.vpc.default_security_group_id] : []
    }

    ssmmessages = {
      service = "ssmmessages"
      private_dns_enabled = var.enable_private_subnet
      subnet_ids = var.enable_private_subnet == true ? module.vpc.private_subnets : []
      security_group_ids = var.enable_private_subnet == true ? [module.vpc.default_security_group_id] : []
    }
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
