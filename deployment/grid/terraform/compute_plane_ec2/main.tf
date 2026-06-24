# Copyright 2024 Amazon.com, Inc. or its affiliates.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

# Worker-plane definition for the ec2 backend: the IAM instance profile, security group,
# container-log group, and the rendered worker user-data (boots N Agent+RIE Compose pairs).
# ORB launches instances directly (it builds its own launch template per fleet request from the
# baked ORB template); this module just produces the role/profile/SG/AMI/user-data ORB consumes.

locals {
  suffix     = var.suffix
  account_id = data.aws_caller_identity.current.account_id
  dns_suffix = data.aws_partition.current.dns_suffix
  partition  = data.aws_partition.current.partition

  worker_log_group_name = "/aws/ec2/${var.cluster_name}/worker-logs"

  user_data_plain = templatefile("${path.module}/user-data.sh.tftpl", {
    region               = var.region
    ecr                  = var.aws_htc_ecr
    agent_image          = "awshpc-lambda:${var.image_tag}"
    rie_image            = "lambda:provided"
    getlayer_image       = "lambda-init:${var.image_tag}"
    lambda_function_name = var.lambda_function_name
    handler              = var.handler
    s3_source            = var.lambda_configuration_s3_source
    ssm_config_param     = var.ssm_config_parameter_name
    compose_s3           = var.compose_plugin_s3_uri
    pair_cpu             = var.pair_cpu
    pair_memory          = var.pair_memory
    agent_cpus           = var.agent_max_cpu / 1000   # millicores → cores for compose `cpus`
    agent_memory         = "${var.agent_max_memory}m" # MiB → compose `mem_limit`
    rie_cpus             = var.lambda_max_cpu / 1000
    rie_memory           = "${var.lambda_max_memory}m"
    log_group            = local.worker_log_group_name
  })
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# Latest AL2023 x86_64 AMI (resolved at apply time)
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}
