# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/
 


resource "kubernetes_namespace" "influxdb" {
  metadata {
    annotations = {
      name = "influxdb"
    }
    name = "influxdb"
  }
  depends_on = [
    module.eks
  ]
}

resource "helm_release" "influxdb" {
  name       = "influxdb"
  chart      = "influxdb"
  namespace  = "influxdb"
  repository = "https://helm.influxdata.com/"

  set {
    name  = "persistence.enabled"
    value = "false"
  }

  set {
    name = "image.repository"
    value = "${var.aws_htc_ecr}/influxdb"
  }

  set {
    name = "service.type"
    value = "LoadBalancer"
  }

  set {
    type = "string"
    name = "service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-internal"
    value = "true"
  }
  set {
    type = "string"
    name = "service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
    value = "nlb"
  }

  values = [
    file("resources/influxdb-conf.yaml")
  ]


  depends_on = [
    kubernetes_namespace.influxdb
  ]

}

data "kubernetes_service" "influxdb_load_balancer" {
  metadata {
    name = "influxdb"
    namespace = "influxdb"
  }
  depends_on = [
    helm_release.influxdb
  ]
}