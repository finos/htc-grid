# Copyright 2024 Amazon.com, Inc. or its affiliates.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

output "instance_role_arn" {
  description = "Worker instance role ARN (ORB orchestrator needs iam:PassRole on this)"
  value       = aws_iam_role.worker.arn
}

output "instance_profile_arn" {
  description = "Worker instance profile ARN (ORB launch template attaches this)"
  value       = aws_iam_instance_profile.worker.arn
}

output "instance_profile_name" {
  description = "Worker instance profile name"
  value       = aws_iam_instance_profile.worker.name
}

output "worker_security_group_id" {
  description = "Worker security group id (ORB launch template references this)"
  value       = aws_security_group.worker.id
}

output "worker_log_group_name" {
  description = "CloudWatch log group for worker container logs"
  value       = aws_cloudwatch_log_group.worker_logs.name
}

output "worker_ami_id" {
  description = "Resolved AL2023 AMI id used by the worker"
  value       = data.aws_ssm_parameter.al2023_ami.value
}

output "worker_user_data_plain" {
  description = "Plain-text cloud-init (ORB base64-encodes it itself when launching)"
  value       = local.user_data_plain
}
