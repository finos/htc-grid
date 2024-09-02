# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


locals {
  redis_engine_version = "7.0"
}


module "htc_data_cache_kms_key" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 2.0"

  description             = "CMK to encrypt htc_data_cache"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true

  key_administrators = local.kms_key_admin_arns

  key_statements = [
    {
      sid    = "Allow CMK KMS Key Access via SQS Service"
      effect = "Allow"
      actions = [
        "kms:Encrypt*",
        "kms:Decrypt*",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:Describe*"
      ]
      resources = ["*"]

      principals = [
        {
          type        = "AWS"
          identifiers = local.kms_key_admin_arns
        }
      ]

      conditions = [
        {
          test     = "StringEquals"
          variable = "kms:ViaService"
          values = [
            "elasticache.${var.region}.${local.dns_suffix}"
          ]
        }
      ]
    }
  ]

  aliases = ["redis/htc-data-cache-${lower(local.suffix)}"]
}


resource "random_password" "htc_data_cache_password" {
  length           = 32
  special          = true
  override_special = "!&#$"
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
}


resource "aws_elasticache_replication_group" "htc_data_cache" {
  #checkov:skip=CKV2_AWS_50:[TODO] Make HTC Data Cache Multi AZ Configrable

  replication_group_id = "htc-data-cache-${lower(local.suffix)}"
  description          = "Replication group for htc_data_cache cluster"
  engine               = "redis"
  engine_version       = "7.0"
  node_type            = "cache.r7g.large"
  parameter_group_name = aws_elasticache_parameter_group.htc_data_cache_config.name
  port                 = 6379
  security_group_ids   = [aws_security_group.allow_incoming_redis.id]
  subnet_group_name    = "htc-data-cache-subnet-${lower(local.suffix)}"

  replicas_per_node_group = 0
  num_node_groups         = 1

  # snapshot_window          = "06:00-08:00"
  snapshot_retention_limit = 1

  transit_encryption_enabled = true
  at_rest_encryption_enabled = true
  auth_token                 = random_password.htc_data_cache_password.result
  kms_key_id                 = module.htc_data_cache_kms_key.key_arn

  depends_on = [
    aws_elasticache_subnet_group.htc_data_cache_subnet_group,
  ]
}


resource "aws_elasticache_subnet_group" "htc_data_cache_subnet_group" {
  name       = "htc-data-cache-subnet-${lower(local.suffix)}"
  subnet_ids = var.vpc_private_subnet_ids
}


resource "aws_security_group" "allow_incoming_redis" {
  name        = "htc-data-cache-${lower(local.suffix)}"
  description = "Allow inbound Redis traffic on tcp/6379"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow inbound Redis traffic on tcp/6379 from within VPC"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Allow inbound Redis access on tcp/6379 from allowed_access_cidr_blocks"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = var.allowed_access_cidr_blocks
  }

  egress {
    description = "Allow outbound Redis access to VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow outbound Redis access to allowed_access_cidr_blocks"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.allowed_access_cidr_blocks
  }
}


resource "aws_elasticache_parameter_group" "htc_data_cache_config" {
  name   = "htc-data-cache-config-${lower(local.suffix)}-${replace(local.redis_engine_version, ".", "-")}"
  family = "redis7"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }
}
