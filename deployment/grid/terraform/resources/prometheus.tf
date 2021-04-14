# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/
 
resource "kubernetes_namespace" "prometheus" {
  metadata {
    annotations = {
      name = "prometheus"
    }
    name = "prometheus"
  }
  depends_on = [
    module.eks
  ]
}

resource "helm_release" "prometheus" {
  name       = "prometheus"
  chart      = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts" 
  namespace  = "prometheus"
  set {
    name  = "nodeExporter.image.repository"
    value = "${var.aws_htc_ecr}/node-exporter"
  }
  set {
    name  = "nodeExporter.image.tag"
    value = var.prometheus_configuration.node_exporter_tag
  }
  set {
    name  = "server.image.repository"
    value = "${var.aws_htc_ecr}/prometheus"
  }
  set {
    name  = "server.image.tag"
    value = var.prometheus_configuration.server_tag
  }
//   set {
//     name  = "image.repository"
//     value = "${var.aws_htc_ecr}/kube-state-metrics"
//   }

  set {
    name  = "alertmanager.persistentVolume.enabled"
    value = "false"
  }

  set {
    name  = "server.persistentVolume.enabled"
    value = "false"
  }
  set {
    name  = "pushgateway.persistentVolume.enabled"
    value = "false"
  }
  set {
    name  = "kube-state-metrics.image.repository"
    value = "${var.aws_htc_ecr}/kube-state-metrics"
  }
  set {
    name  = "kube-state-metrics.image.tag"
    value = var.prometheus_configuration.kube_state_metrics_tag
  }

  set {
    name  = "kube-state-metrics.resources.limits.memory"
    value = "6Gi"
  }
  set {
    name  = "kube-state-metrics.resources.limits.cpu"
    value = "3000m"
  }
  set {
    name  = "kube-state-metrics.resources.requests.memory"
    value = "1Gi"
  }
  set {
    name  = "kube-state-metrics.resources.requests.cpu"
    value = "500m"
  }
  set {
    name  = "alertmanager.image.repository"
    value = "${var.aws_htc_ecr}/alertmanager"
  }
  set {
    name  = "alertmanager.image.tag"
    value = var.prometheus_configuration.alertmanager_tag
  }
  set {
    name  = "pushgateway.image.repository"
    value = "${var.aws_htc_ecr}/pushgateway"
  }
  set {
    name  = "pushgateway.image.tag"
    value = var.prometheus_configuration.pushgateway_tag
  }
  set {
    name  = "configmapReload.prometheus.image.repository"
    value = "${var.aws_htc_ecr}/configmap-reload"
  }
  set {
    name  = "configmapReload.prometheus.image.tag"
    value = var.prometheus_configuration.configmap_reload_tag
  }
  set {
    name  = "configmapReload.alertmanager.image.repository"
    value = "${var.aws_htc_ecr}/configmap-reload"
  }
  set {
    name  = "configmapReload.alertmanager.image.tag"
    value = var.prometheus_configuration.configmap_reload_tag
  }

  values = [
    file("resources/prometheus-conf.yaml")
  ]

  depends_on = [
    kubernetes_namespace.prometheus
  ]

}

