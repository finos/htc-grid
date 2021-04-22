# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

output "redis_url" {
  description = "Redis URL"
  value       = aws_elasticache_cluster.stdin-stdout-cache.cache_nodes.0.address
}

output "s3_bucket_name" {
  description = "Name of the bucket"
  value       = aws_s3_bucket.htc-stdout-bucket.id
}

output "public_api_gateway_url" {
  value = aws_api_gateway_deployment.htc_grid_public_deployment.invoke_url
}

output "private_api_gateway_url" {
  value = aws_api_gateway_deployment.htc_grid_private_deployment.invoke_url
}


output "api_gateway_key" {
  value = aws_api_gateway_api_key.htc_grid_api_key.value
  sensitive = true
}
