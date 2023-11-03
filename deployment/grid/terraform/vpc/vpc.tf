# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


module "vpc_flow_logs_cloudwatch_kms_key" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 2.0"

  description             = "CMK KMS Key used to encrypt vpc_flow_logs CloudWatch Logs"
  deletion_window_in_days = 7

  key_administrators = [
    "arn:${local.partition}:iam::${local.account_id}:root",
    data.aws_caller_identity.current.arn
  ]

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
            "logs.${var.region}.amazonaws.com"
          ]
        }
      ]
      resources = ["*"]
      condition = [
        {
          test     = "ArnLike"
          variable = "kms:EncryptionContext:aws:logs:arn"
          values   = ["arn:${local.partition}:logs:${var.region}:${local.account_id}:*"]
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
  cidr               = "10.0.0.0/16"
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

  default_security_group_ingress = [
    {
      description = "HTTPS Ingress from within VPC"
      type        = "ingress"
      self        = true
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = "10.0.0.0/16"
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
    { for service in toset(["autoscaling", "ecr.api", "ecr.dkr", "ec2", "elasticloadbalancing", "eks", "execute-api", "logs", "monitoring", "sqs", "sts", "ssm", "ssmmessages"]) :
      replace(service, ".", "_") =>
      {
        service             = service
        private_dns_enabled = var.enable_private_subnet
        subnet_ids          = var.enable_private_subnet == true ? module.vpc.private_subnets : []
        security_group_ids  = var.enable_private_subnet == true ? [module.vpc.default_security_group_id] : []
      }
  })
}
