# Copyright 2024 Amazon.com, Inc. or its affiliates.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

output "function_name" {
  description = "ORB orchestrator Lambda function name"
  value       = module.orb_orchestrator.lambda_function_name
}

output "function_arn" {
  description = "ORB orchestrator Lambda function ARN"
  value       = module.orb_orchestrator.lambda_function_arn
}

output "machines_table_name" {
  value = aws_dynamodb_table.orb_state["machines"].name
}

output "state_kms_key_arn" {
  value = module.orb_state_kms_key.key_arn
}
