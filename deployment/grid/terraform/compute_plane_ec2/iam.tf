# Copyright 2024 Amazon.com, Inc. or its affiliates.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

# Instance role + profile for worker instances. The base agent permissions policy
# (from control_plane) already covers SQS/DDB/S3 data+layer/CloudWatch/KMS. The
# supplementary policy adds: SSM config read, worker-log-group writes, and KMS decrypt
# of the SSM config key (when it is a distinct CMK).

resource "aws_iam_role" "worker" {
  name = "role_htc_ec2_worker_${local.suffix}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Effect": "Allow",
      "Principal": { "Service": "ec2.${local.dns_suffix}" }
    }
  ]
}
EOF

  tags = {
    service = "htc-aws"
  }
}

# Same permissions the EKS agent service account gets via IRSA.
resource "aws_iam_role_policy_attachment" "agent_permissions" {
  role       = aws_iam_role.worker.name
  policy_arn = var.htc_agent_permissions_policy_arn
}

# Session Manager (shell + SSM-driven verification) and ECR image pull.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.worker.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  role       = aws_iam_role.worker.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Supplementary: read the SSM config param, decrypt it, write container logs.
resource "aws_iam_policy" "worker_supplementary" {
  name        = "htc-ec2-worker-${local.suffix}-supp"
  description = "EC2 worker: SSM config read + KMS decrypt + worker log group writes"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SsmConfigRead",
      "Action": ["ssm:GetParameter", "ssm:GetParameters"],
      "Resource": "${var.ssm_config_parameter_arn}",
      "Effect": "Allow"
    },
    {
      "Sid": "SsmConfigKmsDecrypt",
      "Action": ["kms:Decrypt"],
      "Resource": "${var.ssm_config_kms_key_arn}",
      "Effect": "Allow"
    },
    {
      "Sid": "WorkerLogGroup",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      "Resource": "${aws_cloudwatch_log_group.worker_logs.arn}:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "worker_supplementary" {
  role       = aws_iam_role.worker.name
  policy_arn = aws_iam_policy.worker_supplementary.arn
}

resource "aws_iam_instance_profile" "worker" {
  name = "htc-ec2-worker-${local.suffix}"
  role = aws_iam_role.worker.name
}
