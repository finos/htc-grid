# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


module "lambda_drainer_cloudwatch_kms_key" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 2.0"

  description             = "CMK to encrypt lambda_drainer CloudWatch Logs"
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

  aliases = ["cloudwatch/lambda/lambda_drainer-${local.suffix}"]
}


# Create zip-archive of a single directory where "pip install" will also be executed (default for python runtime)
module "lambda_drainer" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 5.0"

  source_path     = "../../../source/compute_plane/python/lambda/drainer"
  function_name   = "lambda_drainer-${local.suffix}"
  build_in_docker = true
  docker_image    = local.lambda_build_runtime
  docker_additional_options = [
    "--platform", "linux/amd64",
  ]
  handler     = "handler.lambda_handler"
  memory_size = 1024
  timeout     = 900
  runtime     = var.lambda_runtime

  role_name = "role_lambda_drainer_${local.suffix}"
  role_description = "Lambda role for lambda_drainer-${local.suffix}"
  attach_network_policy = true

  attach_policies = true
  number_of_policies = 1
  policies = [
    aws_iam_policy.lambda_drainer_data_policy.arn
  ]

  attach_cloudwatch_logs_policy = true
  cloudwatch_logs_kms_key_id = module.lambda_drainer_cloudwatch_kms_key.key_arn

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
  count = length(var.eks_worker_groups)

  name                   = var.eks_worker_groups[count.index].node_group_name
  autoscaling_group_name = module.eks.eks_managed_node_groups_autoscaling_group_names[count.index]
  default_result         = "ABANDON"
  heartbeat_timeout      = var.graceful_termination_delay
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"
}


resource "aws_cloudwatch_event_rule" "lifecycle_hook_event_rule" {
  count = length(var.eks_worker_groups)

  name          = "event-lifecyclehook-${count.index}-${local.suffix}"
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
      "${module.eks.eks_managed_node_groups_autoscaling_group_names[count.index]}"
    ]
  }
}
EOF
}


resource "aws_cloudwatch_event_target" "terminate_instance_event" {
  count = length(var.eks_worker_groups)

  rule      = "event-lifecyclehook-${count.index}-${local.suffix}"
  target_id = "lambda"
  arn       = module.lambda_drainer.lambda_function_arn

  depends_on = [
    aws_cloudwatch_event_rule.lifecycle_hook_event_rule,
  ]
}


resource "aws_lambda_permission" "allow_cloudwatch_to_call_lambda_drainer" {
  count = length(aws_cloudwatch_event_rule.lifecycle_hook_event_rule)

  statement_id  = "AllowDrainerExecutionFromCloudWatch-${count.index}"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_drainer.lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lifecycle_hook_event_rule[count.index].arn
}


resource "aws_iam_policy" "lambda_drainer_data_policy" {
  name        = "lambda-drainer-${local.suffix}-data"
  path        = "/"
  description = "Policy for draining nodes of an EKS cluster"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "autoscaling:CompleteLifecycleAction",
        "ec2:DescribeInstances",
        "eks:DescribeCluster",
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*",
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}


#Lambda Drainer EKS Access
resource "kubernetes_cluster_role" "lambda_cluster_access" {
  metadata {
    name = "lambda-cluster-access"
  }

  rule {
    verbs      = ["create", "list", "patch"]
    api_groups = [""]
    resources  = ["pods", "pods/eviction", "nodes"]
  }

  depends_on = [
    module.eks,
  ]
}


resource "kubernetes_cluster_role_binding" "lambda_user_cluster_role_binding" {
  metadata {
    name = "lambda-user-cluster-role-binding"
  }

  subject {
    kind = "User"
    name = "lambda"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "lambda-cluster-access"
  }

  depends_on = [
    module.eks,
  ]
}
