# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/
 

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane."
  value       = module.eks.eks_cluster_endpoint
}

output "certificate_authority" {
  description = "Endpoint for EKS control plane."
  value       = data.aws_eks_cluster.cluster.certificate_authority
}

output "token" {
  description = "authentication token for EKS"
  value       = data.aws_eks_cluster_auth.cluster.token
  sensitive   = true
}

output "nlb_influxdb" {
  description = "url of the NLB in front of the influx DB"
  value = try(data.kubernetes_service.influxdb_load_balancer.status.0.load_balancer.0.ingress.0.hostname,"google.com")
}

output "cognito_userpool_arn" {
  description = "url of the NLB in front of the influx DB"
  value = aws_cognito_user_pool.htc_pool.arn
}

output "cognito_userpool_id" {
  description = "url of the NLB in front of the influx DB"
  value = aws_cognito_user_pool.htc_pool.id
}

output "cognito_userpool_client_id" {
  description = "url of the NLB in front of the influx DB"
  value = aws_cognito_user_pool_client.user_data_client.id
}