# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

output "htc_data_cache_url" {
  description = " URL"
  value       = aws_elasticache_replication_group.htc_data_cache.primary_endpoint_address
}

output "htc_data_bucket_name" {
  description = "Name of the bucket"
  value       = aws_s3_bucket.htc_data_bucket.id
}

output "public_api_gateway_url" {
  value = aws_api_gateway_deployment.htc_public_api_deployment.invoke_url
}

output "private_api_gateway_url" {
  value = aws_api_gateway_deployment.htc_private_api_deployment.invoke_url
}

output "api_gateway_key" {
  value     = aws_api_gateway_api_key.htc_private_api_key.value
  sensitive = true
}
