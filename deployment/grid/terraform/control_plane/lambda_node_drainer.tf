# Copyright 2023 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


module "node_drainer_cloudwatch_kms_key" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 2.0"

  description             = "CMK KMS Key used to encrypt node_drainer CloudWatch Logs"
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
          values   = ["arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/${var.lambda_name_node_drainer}"]
        }
      ]
    }
  ]

  aliases = ["cloudwatch/lambda/${var.lambda_name_node_drainer}"]
}


# Create zip-archive of a single directory where "pip install" will also be executed (default for python runtime)
module "node_drainer" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 5.0"

  source_path     = "../../../source/compute_plane/python/lambda/drainer"
  function_name   = var.lambda_name_node_drainer
  build_in_docker = true
  docker_image    = local.lambda_build_runtime
  docker_additional_options = [
    "--platform", "linux/amd64",
  ]
  handler     = "handler.lambda_handler"
  memory_size = 1024
  timeout     = 900
  runtime     = var.lambda_runtime

  role_name             = "role_node_drainer_${local.suffix}"
  role_description      = "Lambda role for node_drainer-${local.suffix}"
  attach_network_policy = true

  attach_policies    = true
  number_of_policies = 1
  policies = [
    aws_iam_policy.node_drainer_data_policy.arn
  ]

  attach_cloudwatch_logs_policy = true
  cloudwatch_logs_kms_key_id    = module.node_drainer_cloudwatch_kms_key.key_arn

  attach_tracing_policy = true
  tracing_mode          = "Active"

  vpc_subnet_ids         = var.vpc_private_subnet_ids
  vpc_security_group_ids = [var.vpc_default_security_group_id]

  environment_variables = {
    CLUSTER_NAME = var.cluster_name
  }

  tags = {
    service = "htc-aws"
  }
}


resource "aws_autoscaling_lifecycle_hook" "drainer_hook" {
  for_each = var.eks_managed_node_groups #local.eks_managed_node_groups_autoscaling_group_names

  name                   = "autoscaling-lifecyclehook-${each.key}-${local.suffix}"
  autoscaling_group_name = each.value.name
  default_result         = "ABANDON"
  heartbeat_timeout      = var.graceful_termination_delay
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"
}


resource "aws_cloudwatch_event_rule" "lifecycle_hook_event_rule" {
  for_each = var.eks_managed_node_groups #local.eks_managed_node_groups_autoscaling_group_names

  name          = "event-lifecyclehook-${each.key}-${local.suffix}"
  description   = "Fires event when an EC2 instance is terminated"
  event_pattern = <<EOF
{
  "detail-type": [
    "EC2 Instance-terminate Lifecycle Action"
  ],
  "source": [
    "aws.autoscaling"
  ],
  "detail": {
    "AutoScalingGroupName": [
      "${each.value.name}"
    ]
  }
}
EOF
}


resource "aws_cloudwatch_event_target" "terminate_instance_event" {
  for_each = var.eks_managed_node_groups #local.eks_managed_node_groups_autoscaling_group_names

  rule      = "event-lifecyclehook-${each.key}-${local.suffix}"
  target_id = "lambda"
  arn       = module.node_drainer.lambda_function_arn

  depends_on = [
    aws_cloudwatch_event_rule.lifecycle_hook_event_rule,
  ]
}


resource "aws_lambda_permission" "allow_cloudwatch_to_call_node_drainer" {
  for_each = aws_cloudwatch_event_rule.lifecycle_hook_event_rule

  statement_id  = "AllowDrainerExecutionFromCloudWatch-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = module.node_drainer.lambda_function_name
  principal     = "events.${local.dns_suffix}"
  source_arn    = each.value.arn
}


resource "aws_iam_policy" "node_drainer_data_policy" {
  name        = "lambda-drainer-${local.suffix}-data"
  path        = "/"
  description = "Policy for draining nodes of an EKS cluster"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "autoscaling:CompleteLifecycleAction"
      ],
      "Resource": ${jsonencode(compact(flatten([for k, v in var.eks_managed_node_groups : v.arn])))},
      "Effect": "Allow"
    },
    {
      "Action": [
        "ec2:DescribeInstances",
        "eks:DescribeCluster",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*",
      "Effect": "Allow"
    }
  ]
}
EOF
}
