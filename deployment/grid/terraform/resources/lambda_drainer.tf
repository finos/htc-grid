# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/




# Create zip-archive of a single directory where "pip install" will also be executed (default for python runtime)
module "lambda_drainer" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "v1.48.0"
  source_path = "../../../source/compute_plane/python/lambda/drainer"
  function_name =  "lambda_drainer-${local.suffix}"
  handler = "handler.lambda_handler"
  memory_size = 1024
  timeout = 900
  create_role = false
  lambda_role = aws_iam_role.role_lambda_drainer.arn
/*   vpc_config {
    subnet_ids = var.vpc_private_subnet_ids
    security_group_ids = [var.vpc_default_security_group_id]
  } */
  environment_variables = {
      CLUSTER_NAME=var.cluster_name
  }
   tags = {
    service     = "htc-aws"
  }
  runtime     = var.lambda_runtime
  build_in_docker = true
  docker_image = "${var.aws_htc_ecr}/lambda-build:build-${var.lambda_runtime}"

}


resource "aws_iam_role" "role_lambda_drainer" {
  name = "role_lambda_drainer-${local.suffix}"
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



resource "aws_autoscaling_lifecycle_hook" "drainer_hook" {
  count = length( var.eks_worker_groups)
  #name  = var.user_names[count.index]
  name                   = var.eks_worker_groups[count.index].name
  autoscaling_group_name = module.eks.workers_asg_names[count.index]
  default_result         = "ABANDON"
  heartbeat_timeout      = var.graceful_termination_delay
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"

}


resource "aws_cloudwatch_event_rule" "lifecycle_hook_event_rule" {
  count = length( var.eks_worker_groups)
  name                = "event-lifecyclehook-${count.index}-${local.suffix}"
  description         = "Fires event when an EC2 instance is terminated"
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
      "${module.eks.workers_asg_names[count.index]}"
    ]
  }
}
EOF
}

resource "aws_cloudwatch_event_target" "terminate_instance_event" {
  count = length( var.eks_worker_groups)
  rule      = "event-lifecyclehook-${count.index}-${local.suffix}"
  target_id = "lambda"
  #arn       = aws_lambda_function.drainer.arn
  arn       = module.lambda_drainer.this_lambda_function_arn
  depends_on =[
    aws_cloudwatch_event_rule.lifecycle_hook_event_rule
  ]
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_lambda_drainer" {
  count = length( aws_cloudwatch_event_rule.lifecycle_hook_event_rule)
  statement_id  = "AllowDrainerExecutionFromCloudWatch-${count.index}"
  action        = "lambda:InvokeFunction"
  #function_name = aws_lambda_function.drainer.function_name
  function_name = module.lambda_drainer.this_lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lifecycle_hook_event_rule[count.index].arn
}


# resource "aws_cloudwatch_log_group" "scaling_metrics_logs" {
#   name = "/aws/lambda/${aws_lambda_function.scaling_metrics.function_name}"
#   retention_in_days = 14
# }


#Agent permissions
data "aws_iam_policy_document" "lambda_drainer_policy_document" {
  statement {
    sid    = ""
    effect = "Allow"

    actions = [
        "ec2:CreateNetworkInterface",
        "ec2:DeleteNetworkInterface",
        "ec2:DescribeNetworkInterfaces",
        "autoscaling:CompleteLifecycleAction",
        "ec2:DescribeInstances",
        "eks:DescribeCluster",
        "sts:GetCallerIdentity"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "lambda_drainer_policy" {
  name_prefix = "lambda-drainer-policy"
  description = "Policy for draining  nodes of an EKS cluster"
  policy      = data.aws_iam_policy_document.lambda_drainer_policy_document.json
}


resource "aws_iam_role_policy_attachment" "lambda_drainer_basic_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.role_lambda_drainer.name
}

resource "aws_iam_role_policy_attachment" "lambda_drainer_policy_attachment" {
  policy_arn = aws_iam_policy.lambda_drainer_policy.arn
  role       = aws_iam_role.role_lambda_drainer.name
}

