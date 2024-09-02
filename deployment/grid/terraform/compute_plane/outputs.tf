# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


output "cluster_name" {
  description = "EKS Cluster Name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane."
  value       = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  description = "OIDC Provider ARN for the EKS Cluster"
  value       = module.eks.oidc_provider_arn
}

output "certificate_authority" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "nlb_influxdb" {
  description = "url of the NLB in front of the influx DB"
  value       = data.kubernetes_service_v1.influxdb_load_balancer.status[0].load_balancer[0].ingress[0].hostname
}

output "grafana_ingress_domain" {
  description = "Ingress Domain for Grafana"
  value       = "https://${data.kubernetes_ingress_v1.grafana_ingress.status[0].load_balancer[0].ingress[0].hostname}"
}

output "eks_managed_node_groups" {
  description = "Map of names and ARNs of EKS Managed Node Group ASGs"
  value       = local.eks_managed_node_groups
}
