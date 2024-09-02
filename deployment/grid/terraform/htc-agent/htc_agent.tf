# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


module "htc-agent" {
  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "~>1.0"

  name             = "htc-agent"
  chart            = "agent-htc-lambda"
  repository       = var.agent_chart_url
  namespace        = var.agent_namespace
  create_namespace = true
  create_policy    = false

  set = [
    {
      name  = "fullnameOverride"
      value = var.agent_name
    },
    {
      name  = "terminationGracePeriodSeconds"
      value = var.termination_grace_period
    },
    #lambda configuration
    {
      name  = "storage"
      value = var.lambda_configuration_storage_type
    },
    {
      name  = "lambda.s3Source"
      value = var.lambda_configuration_s3_source
    },
    {
      name  = "lambda.functionName"
      value = var.lambda_configuration_function_name
    },
    {
      name  = "lambda.handler"
      value = local.handler
    },
    #Agent section
    {
      name  = "imageAgent.repository"
      value = var.agent_image_repository
    },
    {
      name  = "imageAgent.version"
      value = var.agent_image_tag
    },
    {
      name  = "imageAgent.pullPolicy"
      value = var.agent_pull_policy
    },
    {
      name  = "resourcesAgent.limits.cpu"
      value = "${var.agent_max_cpu}m"
    },
    {
      name  = "resourcesAgent.requests.cpu"
      value = "${var.agent_min_cpu}m"
    },
    {
      name  = "resourcesAgent.limits.memory"
      value = "${var.agent_max_memory}Mi"
    },
    {
      name  = "resourcesAgent.requests.memory"
      value = "${var.agent_min_memory}Mi"
    },
    #Test section
    {
      name  = "imageTestAgent.repository"
      value = var.test_agent_image_repository
    },
    {
      name  = "imageTestAgent.version"
      value = var.test_agent_image_tag
    },
    {
      name  = "imageTestAgent.pullPolicy"
      value = var.test_pull_policy
    },
    #Lambda section
    {
      name  = "imageLambdaServer.repository"
      value = var.lambda_image_repository
    },
    {
      name  = "imageLambdaServer.runtime"
      value = var.lambda_image_tag
    },
    {
      name  = "imageLambdaServer.pullPolicy"
      value = var.lambda_pull_policy
    },
    {
      name  = "resourcesLambdaServer.limits.cpu"
      value = "${var.lambda_max_cpu}m"
    },
    {
      name  = "resourcesLambdaServer.requests.cpu"
      value = "${var.lambda_min_cpu}m"
    },
    {
      name  = "resourcesLambdaServer.limits.memory"
      value = "${var.lambda_max_memory}Mi"
    },
    {
      name  = "resourcesLambdaServer.requests.memory"
      value = "${var.lambda_min_memory}Mi"
    },
    #get-layer section
    {
      name  = "imageGetLayer.repository"
      value = var.get_layer_image_repository
    },
    {
      name  = "imageGetLayer.version"
      value = var.get_layer_image_tag
    },
    {
      name  = "imageGetLayer.pullPolicy"
      value = var.get_layer_pull_policy
    },
    {
      name  = "hpa.metric.namespace"
      value = var.namespace_metrics
    },
    {
      name  = "hpa.metric.dimensionName"
      value = var.dimension_name_metrics
    },
    {
      name  = "hpa.metric.dimensionValue"
      value = var.dimension_value_metrics
    },
    {
      name  = "hpa.metric.name"
      value = var.metric_name
    },
    {
      name  = "hpa.metric.targetValue"
      value = var.htc_agent_target_value
    },
    {
      name  = "hpa.metric.region"
      value = var.region
    },
    {
      name  = "hpa.maxAgent"
      value = var.max_htc_agents
    },
    {
      name  = "hpa.minAgent"
      value = var.min_htc_agents
    }
  ]

  set_irsa_names = ["serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"]

  # IAM role for service account (IRSA)
  create_role = true
  role_name   = "role_htc_agent_sa-${local.suffix}"
  role_policies = {
    agent_permissions = var.htc_agent_permissions_policy_arn
  }

  oidc_providers = {
    this = {
      provider_arn    = var.eks_oidc_provider_arn
      service_account = "htc-agent-sa"
    }
  }
}
