# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


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
  create_role = false
  lambda_role = aws_iam_role.role_lambda_drainer.arn

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


#Lambda Drainer IAM Role & Permissions
resource "aws_iam_role" "role_lambda_drainer" {
  name               = "role_lambda_drainer-${local.suffix}"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}


resource "aws_iam_policy" "lambda_drainer_logging_policy" {
  name        = "lambda_drainer_logging_policy-${local.suffix}"
  path        = "/"
  description = "IAM policy for logging from the lambda_drainer lambda"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:${local.partition}:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}


resource "aws_iam_policy" "lambda_drainer_data_policy" {
  name        = "lambda-drainer-policy-${local.suffix}"
  path        = "/"
  description = "Policy for draining nodes of an EKS cluster"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ec2:CreateNetworkInterface",
        "ec2:DeleteNetworkInterface",
        "ec2:DescribeNetworkInterfaces",
        "autoscaling:CompleteLifecycleAction",
        "ec2:DescribeInstances",
        "eks:DescribeCluster",
        "sts:GetCallerIdentity",
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ],
      "Resource": "*",
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}


resource "aws_iam_role_policy_attachment" "lambda_drainer_logs_attachment" {
  role       = aws_iam_role.role_lambda_drainer.name
  policy_arn = aws_iam_policy.lambda_drainer_logging_policy.arn
}


resource "aws_iam_role_policy_attachment" "lambda_drainer_data_attachment" {
  role       = aws_iam_role.role_lambda_drainer.name
  policy_arn = aws_iam_policy.lambda_drainer_data_policy.arn
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
