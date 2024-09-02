# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

output "agent_config" {
  description = "file name for the agent configuration"
  value       = abspath(local_file.agent_config_file.filename)
}

output "public_api_endpoint" {
  description = "Public API endpoint for the HTC grid"
  value       = module.control_plane.public_api_gateway_url
}

output "private_api_endpoint" {
  description = "Private API endpoint for the HTC grid"
  value       = module.control_plane.private_api_gateway_url
}

output "user_pool_id" {
  description = "UserPoolID of the Cognito User Pool created"
  value       = module.control_plane.cognito_userpool_id
}

output "user_pool_arn" {
  description = "ARN of the user pool created"
  value       = module.control_plane.cognito_userpool_arn
}

output "user_pool_client_id" {
  description = "ClientID of the Cognito User Pool created"
  value       = module.control_plane.cognito_userpool_client_id
}

output "grafana_ingress_domain" {
  description = "Ingress Domain for Grafana"
  value       = module.compute_plane.grafana_ingress_domain
}

output "grafana_admin_password" {
  description = "The password for the admin user for Grafana"
  value       = local.grafana_admin_password
  sensitive   = true
}
