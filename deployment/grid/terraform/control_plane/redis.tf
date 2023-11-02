# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


module "stdin_stdout_cache_kms_key" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 2.0"

  description             = "CMK to encrypt stdin_stdout_cache"
  deletion_window_in_days = 7

  key_administrators = [
    data.aws_caller_identity.current.arn
  ]

  aliases = ["redis/stdin-stdout-cache-${lower(local.suffix)}"]
}


locals {
  redis_engine_version = "7.0"
}

resource "aws_elasticache_replication_group" "stdin_stdout_cache" {
  replication_group_id = "stdin-stdout-cache-${lower(local.suffix)}"
  description          = "Replication group for stdin_stdout_cache cluster"
  engine               = "redis"
  engine_version       = "7.0"
  node_type            = "cache.r7g.large"
  parameter_group_name = aws_elasticache_parameter_group.cache_config.name
  port                 = 6379
  security_group_ids   = [aws_security_group.allow_incoming_redis.id]
  subnet_group_name    = "stdin-stdout-cache-subnet-${lower(local.suffix)}"

  replicas_per_node_group = 0
  num_node_groups         = 1

  # snapshot_window          = "06:00-08:00"
  snapshot_retention_limit = 1

  transit_encryption_enabled = true
  at_rest_encryption_enabled = true
  kms_key_id                 = module.stdin_stdout_cache_kms_key.key_arn

  depends_on = [
    aws_elasticache_subnet_group.io_redis_subnet_group,
  ]
}


resource "aws_elasticache_subnet_group" "io_redis_subnet_group" {
  name       = "stdin-stdout-cache-subnet-${lower(local.suffix)}"
  subnet_ids = var.vpc_private_subnet_ids
}


resource "aws_security_group" "allow_incoming_redis" {
  name        = "redis-io-cache-${lower(local.suffix)}"
  description = "Allow inbound Redis traffic on tcp/6379"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow inbound Redis traffic on tcp/6379 from within VPC"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow outbound Redis traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_elasticache_parameter_group" "cache_config" {
  name   = "cache-config-${lower(local.suffix)}-${replace(local.redis_engine_version, ".", "-")}"
  family = "redis7"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }
}
