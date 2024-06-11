# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


locals {
  vpc_cidr_range             = "10.0.0.0/16"
  allowed_access_cidr_blocks = join(",", concat([local.vpc_cidr_range], var.allowed_access_cidr_blocks))
}


module "vpc_flow_logs_cloudwatch_kms_key" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 2.0"

  description             = "CMK KMS Key used to encrypt vpc_flow_logs CloudWatch Logs"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true

  key_administrators = local.kms_key_admin_arns

  key_statements = [
    {
      sid = "Allow Lambda functions to encrypt/decrypt CloudWatch Logs"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
        "kms:Decrypt",
      ]
      effect = "Allow"
      principals = [
        {
          type = "Service"
          identifiers = [
            "logs.${var.region}.${local.dns_suffix}"
          ]
        }
      ]
      resources = ["*"]
      conditions = [
        {
          test     = "ArnEquals"
          variable = "kms:EncryptionContext:aws:logs:arn"
          values   = ["arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:/aws/vpc-flow-logs/${var.cluster_name}-vpc"]
        }
      ]
    }
  ]

  aliases = ["cloudwatch/vpc/${var.cluster_name}-vpc"]
}


module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name               = "${var.cluster_name}-vpc"
  cidr               = local.vpc_cidr_range
  azs                = data.aws_availability_zones.available.names
  private_subnets    = local.private_subnets
  public_subnets     = local.public_subnets
  enable_nat_gateway = !var.enable_private_subnet
  single_nat_gateway = !var.enable_private_subnet
  # Required for private endpoints
  enable_dns_hostnames = true
  enable_dns_support   = true

  map_public_ip_on_launch = false

  enable_flow_log                           = true
  create_flow_log_cloudwatch_iam_role       = true
  create_flow_log_cloudwatch_log_group      = true
  flow_log_cloudwatch_log_group_kms_key_id  = module.vpc_flow_logs_cloudwatch_kms_key.key_arn
  flow_log_max_aggregation_interval         = 60
  flow_log_cloudwatch_log_group_name_prefix = "/aws/vpc-flow-logs/"
  flow_log_cloudwatch_log_group_name_suffix = "${var.cluster_name}-vpc"

  # Disable dedicated Private Subnet ACL (as using default)
  private_dedicated_network_acl = false
  private_inbound_acl_rules     = []
  private_outbound_acl_rules    = []

  # Disable dedicated Public Subnet ACL (as using default)
  public_dedicated_network_acl = false
  public_inbound_acl_rules     = []
  public_outbound_acl_rules    = []

  default_security_group_ingress = [
    {
      description = "HTTPS Ingress from within VPC"
      type        = "ingress"
      self        = true
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = local.allowed_access_cidr_blocks
    }
  ]

  default_security_group_egress = [
    {
      description      = "Default allow ALL Egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = "0.0.0.0/0"
      ipv6_cidr_blocks = "::/0"
    }
  ]

  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}


module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 5.0"

  vpc_id             = module.vpc.vpc_id
  security_group_ids = [module.vpc.default_security_group_id]
  create             = true

  endpoints = merge({
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = flatten([module.vpc.intra_route_table_ids, module.vpc.private_route_table_ids, module.vpc.public_route_table_ids])
    }
    dynamodb = {
      service         = "dynamodb"
      service_type    = "Gateway"
      route_table_ids = flatten([module.vpc.intra_route_table_ids, module.vpc.private_route_table_ids, module.vpc.public_route_table_ids])
    }
    },
    { for service in toset(["autoscaling", "ecr.api", "ecr.dkr", "ec2", "elasticloadbalancing", "eks", "execute-api", "logs", "monitoring", "sqs", "sts", "ssm", "ssmmessages", "xray"]) :
      replace(service, ".", "_") =>
      {
        service             = service
        private_dns_enabled = var.enable_private_subnet
        subnet_ids          = var.enable_private_subnet == true ? module.vpc.private_subnets : []
        security_group_ids  = var.enable_private_subnet == true ? [module.vpc.default_security_group_id] : []
      }
  })
}
