# Copyright 2023 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


# HTC Agent permissions
#trivy:ignore:AVD-AWS-0057 Allow sensitive permissions on individual resources
resource "aws_iam_policy" "htc_agent_permissions" {
  #checkov:skip=AVD-AWS-0057:Allow sensitive permissions on individual resources

  name        = "htc_agent_permissions_policy_${local.suffix}"
  path        = "/"
  description = "IAM policy for HTC Agent Permissions"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "dynamodb:Query",
        "dynamodb:Scan",
        "dynamodb:BatchGetItem",
        "dynamodb:PutItem",
        "dynamodb:BatchWriteItem",
        "dynamodb:UpdateItem",
        "dynamodb:DescribeStream",
        "dynamodb:DescribeTable"
      ],
      "Resource": [
        "${module.htc_dynamodb_table.dynamodb_table_arn}",
        "${module.htc_dynamodb_table.dynamodb_table_arn}/index/*"
      ],
      "Effect": "Allow"
    },
    {
      "Action": [
        "sqs:GetQueueUrl",
        "sqs:GetQueueAttributes",
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility"
      ],
      "Resource": ${jsonencode(local.sqs_queue_and_dlq_arns)},
      "Effect": "Allow"
    },
    {
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": ${jsonencode(local.s3_bucket_arns)},
      "Effect": "Allow"
    },
    {
      "Action": [
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:PutObject",
        "s3:PutObjectAcl"
      ],
      "Resource": ${jsonencode([for k in local.s3_bucket_arns : "${k}/*"])},
      "Effect": "Allow"
    },
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:DescribeLogStreams",
        "logs:PutLogEvents"
      ],
      "Resource": "${aws_cloudwatch_log_group.global_error_group.arn}:*",
      "Effect": "Allow"
    },
    {
      "Action": [
        "cloudwatch:PutMetricData",
        "cloudwatch:GetMetricData",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:ListMetrics"
      ],
      "Resource": "*",
      "Effect": "Allow"
    },
    {
      "Action": [
        "route53:AssociateVPCWithHostedZone"
      ],
      "Resource": "*",
      "Effect": "Allow"
    },
    {
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ],
      "Resource": ${jsonencode(local.control_plane_kms_key_arns)},
      "Effect": "Allow"
    }
  ]
}
EOF
}


#ECR Pull Through Cache Permissions
resource "aws_iam_policy" "ecr_pull_through_cache_policy" {
  name        = "ecr_pull_through_cache_policy_${local.suffix}"
  path        = "/"
  description = "IAM policy for ECR Pull-Through-Cache Permissions"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PullThroughCacheFromReadOnlyRole",
      "Action": [
        "ecr:CreateRepository",
        "ecr:BatchImportUpstreamImage"
      ],
      "Resource": [
        "arn:${local.partition}:ecr:${var.region}:${local.account_id}:repository/ecr-public/*",
        "arn:${local.partition}:ecr:${var.region}:${local.account_id}:repository/quay/*",
        "arn:${local.partition}:ecr:${var.region}:${local.account_id}:repository/registry-k8s-io/*"
      ],
      "Effect": "Allow"
    }
  ]
}
EOF
}


# Lambda Data Policy Permssions
#trivy:ignore:AVD-AWS-0057 Allow sensitive permissions on individual resources
resource "aws_iam_policy" "lambda_data_policy" {
  #checkov:skip=AVD-AWS-0057:Allow sensitive permissions on individual resources

  name        = "lambda_data_policy_${local.suffix}"
  path        = "/"
  description = "IAM Policy that controls the data access for Control Plane Lambdas"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "dynamodb:Query",
        "dynamodb:Scan",
        "dynamodb:BatchGetItem",
        "dynamodb:PutItem",
        "dynamodb:BatchWriteItem",
        "dynamodb:UpdateItem",
        "dynamodb:DescribeStream",
        "dynamodb:DescribeTable"
      ],
      "Resource": [
        "${module.htc_dynamodb_table.dynamodb_table_arn}",
        "${module.htc_dynamodb_table.dynamodb_table_arn}/index/*"
      ],
      "Effect": "Allow"
    },
    {
      "Action": [
        "sqs:GetQueueUrl",
        "sqs:GetQueueAttributes",
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility"
      ],
      "Resource": ${jsonencode(local.sqs_queue_and_dlq_arns)},
      "Effect": "Allow"
    },
    {
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": ${jsonencode(local.s3_bucket_arns)},
      "Effect": "Allow"
    },
    {
      "Action": [
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:PutObject",
        "s3:PutObjectAcl"
      ],
      "Resource": ${jsonencode([for k in local.s3_bucket_arns : "${k}/*"])},
      "Effect": "Allow"
    },
    {
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ],
      "Resource": ${jsonencode(local.control_plane_kms_key_arns)},
      "Effect": "Allow"
    }
  ]
}
EOF
}


# API Gateway CloudWatch Role & Permissions
resource "aws_iam_role" "apigateway_cloudwatch_role" {
  name               = "role_apigw_cw_${local.suffix}"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "apigateway.${local.dns_suffix}"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "apigateway_cloudwatch_policy_attachment" {
  role       = aws_iam_role.apigateway_cloudwatch_role.id
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "apigateway_account" {
  cloudwatch_role_arn = aws_iam_role.apigateway_cloudwatch_role.arn
}
