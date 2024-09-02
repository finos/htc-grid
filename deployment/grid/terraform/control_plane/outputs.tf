# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

output "htc_data_cache_url" {
  description = "HTC Data Cache URL"
  value       = aws_elasticache_replication_group.htc_data_cache.primary_endpoint_address
}

output "htc_data_bucket_name" {
  description = "HTC Data Bucket Name"
  value       = module.htc_data_bucket.s3_bucket_id #aws_s3_bucket.htc_data_bucket.id
}

output "htc_data_bucket_key_arn" {
  description = "HTC Data Bucket KMS Key ARN"
  value       = module.htc_data_bucket_kms_key.key_arn
}

output "public_api_gateway_url" {
  value = aws_api_gateway_stage.htc_public_api_stage.invoke_url
}

output "private_api_gateway_url" {
  value = aws_api_gateway_stage.htc_private_api_stage.invoke_url
}

output "api_gateway_key" {
  value     = aws_api_gateway_api_key.htc_private_api_key.value
  sensitive = true
}

output "htc_agent_permissions_policy_arn" {
  value = aws_iam_policy.htc_agent_permissions.arn
}

output "ecr_pull_through_cache_policy_arn" {
  value = aws_iam_policy.ecr_pull_through_cache_policy.arn
}

output "node_drainer_lambda_role_arn" {
  value = module.node_drainer.lambda_role_arn
}

output "htc_data_cache_password" {
  value     = random_password.htc_data_cache_password.result
  sensitive = true
}

output "cognito_domain_name" {
  description = "Cognito Domain Name"
  value       = local.cognito_domain_name
}

output "cognito_userpool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.htc_pool.id
}

output "cognito_userpool_arn" {
  description = "Cognito User Pool ARN"
  value       = aws_cognito_user_pool.htc_pool.arn
}

output "cognito_userpool_client_id" {
  description = "Cognito User Pool Client ID"
  value       = aws_cognito_user_pool_client.user_data_client.id
}
