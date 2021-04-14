# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/
 
# Policy to Fluentd add to Worker Role
data "aws_iam_policy_document" "fluentd_document" {
  statement {
    effect = "Allow"

    actions = [
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "fluentd_policy" {
  name_prefix = "fluentd-${module.eks.cluster_id}"
  description = "fluentd policy for cluster ${module.eks.cluster_id}"
  policy      = data.aws_iam_policy_document.fluentd_document.json
}

resource "aws_iam_role_policy_attachment" "fluentd_policy_attach" {
  policy_arn = aws_iam_policy.fluentd_policy.arn
  role       = module.eks.worker_iam_role_name
}


#Agent permissions
data "aws_iam_policy_document" "worker_assume_role_agent_permitions_document" {
  statement {
    sid    = ""
    effect = "Allow"

    actions = [
      "sqs:*",
      "dynamodb:*",
      "lambda:*",
      "logs:*",
      "s3:*",
      "firehose:*",
      "cloudwatch:PutMetricData",
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
      "route53:AssociateVPCWithHostedZone"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "worker_assume_role_agent_permitions_policy" {
  name_prefix = "eks-worker-assume-agent-${module.eks.cluster_id}"
  description = "EKS worker node policy for agent in  cluster ${module.eks.cluster_id}"
  policy      = data.aws_iam_policy_document.worker_assume_role_agent_permitions_document.json
}

resource "aws_iam_role_policy_attachment" "worker_assume_role_agent_permitions_document" {
  policy_arn = aws_iam_policy.worker_assume_role_agent_permitions_policy.arn
  role       = module.eks.worker_iam_role_name
}

#Workers Auto Scaling policy
data "aws_iam_policy_document" "worker_autoscaling_document" {
  statement {
    sid    = "eksWorkerAutoscalingAll"
    effect = "Allow"

    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
      "ec2:DescribeLaunchTemplateVersions",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "eksWorkerAutoscalingOwn"
    effect = "Allow"

    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "autoscaling:UpdateAutoScalingGroup",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "worker_autoscaling_policy" {
  name_prefix = "eks-worker-autoscaling-${module.eks.cluster_id}"
  description = "EKS worker node autoscaling policy for cluster ${module.eks.cluster_id}"
  policy      = data.aws_iam_policy_document.worker_autoscaling_document.json
}

resource "aws_iam_role_policy_attachment" "workers_autoscaling_attach" {
  policy_arn = aws_iam_policy.worker_autoscaling_policy.arn
  role       = module.eks.worker_iam_role_name
}

resource "aws_iam_role_policy_attachment" "workers_xray_attach" {
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
  role       = module.eks.worker_iam_role_name
}


resource "aws_iam_role_policy_attachment" "appmesh_attach" {
  policy_arn = "arn:aws:iam::aws:policy/AWSAppMeshFullAccess"
  role       = module.eks.worker_iam_role_name
}


resource "aws_iam_role_policy_attachment" "cloudmap_attach" {
  policy_arn = "arn:aws:iam::aws:policy/AWSCloudMapFullAccess"
  role       = module.eks.worker_iam_role_name
}

resource "aws_iam_policy" "alb_policy" {
   # ... other configuration ...

   policy = file("resources/iam-policy-alb.json")
 }

resource "aws_iam_role_policy_attachment" "alb_policy_attach" {
  policy_arn = aws_iam_policy.alb_policy.arn
  role       = module.eks.worker_iam_role_name
}
