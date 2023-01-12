# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/



#Agent permissions
data "aws_iam_policy_document" "agent_permissions" {
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

#Agent permissions
data "aws_iam_policy_document" "eks_pull_through_cache_permission" {
  statement {
    sid    = "PullThroughCacheFromReadOnlyRole"
    effect = "Allow"

    actions = [
      "ecr:CreateRepository",
      "ecr:BatchImportUpstreamImage"
    ]

    resources = [
      "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/ecr-public/*",
      "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/quay/*"
    ]
  }
}


resource  aws_iam_policy "agent_permissions" {
  description = "The permission required by the HTC agent"
  policy = data.aws_iam_policy_document.agent_permissions.json
}

resource  aws_iam_policy "eks_pull_through_cache_permission" {
  description = "The permissions for the kubelet to use ECR pull through cache"
  policy = data.aws_iam_policy_document.eks_pull_through_cache_permission.json
}