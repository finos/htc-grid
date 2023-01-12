# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

output "agent_config" {
  description = "file name for the agent configuration"
  value       = abspath(local_file.agent_config_file.filename)
}

output "public_api_endpoint" {
  description = "Public API endpoint for the HTC grid"
  value = module.control_plane.public_api_gateway_url
}

output "private_api_endpoint" {
  description = "Private API endpoint for the HTC grid"
  value = module.control_plane.private_api_gateway_url
}

output "user_pool_arn" {
  description = "ARN of the user pool created"
  value = module.compute_plane.cognito_userpool_arn
}

output "grafana_admin_password" {
  value       = local.grafana_admin_password
  description = "The password for grafana."
  sensitive   = true
}

output "user_pool_id" {
  description = "Userpool id of the user pool created"
  value = module.compute_plane.cognito_userpool_id
}

output "user_pool_client_id" {
  description = "Client id of the user pool created"
  value = module.compute_plane.cognito_userpool_client_id
}