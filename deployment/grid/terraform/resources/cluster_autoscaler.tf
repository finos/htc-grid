# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

resource "helm_release" "cluster_autoscaler" {
  name       = "ca"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  repository = "https://kubernetes.github.io/autoscaler"

  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }


  set {
    name  = "awsRegion"
    value = var.region
  }

  set {
    name  = "image.repository"
    value = "${var.aws_htc_ecr}/cluster-autoscaler"

  }

  set {
    name = "image.tag"
    value = var.k8s_ca_version
  }

  values = [
    file("resources/ca_placement_conf.yaml"),
  ]

}

