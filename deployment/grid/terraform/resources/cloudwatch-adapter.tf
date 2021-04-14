# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/
 
# Kubernetes Event-driven Autoscaler
resource "kubernetes_namespace" "cloudwatch-adapter" {
  metadata {
    annotations = {
      name = "cw-adapter"
    }
    name = "custom-metrics"
  }
  depends_on = [
    module.eks
  ]
}

resource "helm_release" "cloudwatch-adapter" {
  name       = "cloudwatch-adapter"
  chart      = "./resources/charts/cloudwatch-adapter/${var.cwa_version}"
  namespace  = "custom-metrics"
  depends_on = [
    module.eks,
    kubernetes_namespace.cloudwatch-adapter
  ]

  set {
    name  = "image.repository"
    value = "${var.aws_htc_ecr}/k8s-cloudwatch-adapter"
  }


  set {
    name  = "image.tag"
    value = var.cwa_version
  }

  set {
    name  = "metric.namespace"
    value = var.namespace_metrics
  }

  set {
    name  = "metric.name"
    value = var.metric_name
  }

  set {
    name  = "metric.dimensionName"
    value = var.dimension_name_metrics
  }
  set {
    name  = "metric.dimensionValue"
    value = var.cluster_name
  }

  set {
    name  = "metric.averagePeriod"
    value = var.average_period
  }

  set {
    name  = "hpa.deploymentName"
    value = var.htc_agent_name
  }

  set {
    name  = "hpa.deploymentNamespace"
    value = var.htc_agent_namespace
  }

  set {
    name  = "hpa.minReplicas"
    value = var.min_htc_agents
  }

  set {
    name  = "hpa.maxReplicas"
    value = var.max_htc_agents
  }

  set {
    name  = "hpa.targetValue"
    value = var.htc_agent_target_value
  }

}