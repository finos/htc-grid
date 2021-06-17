# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


resource "helm_release" "alb_ingress_controller" {
  name       = "alb-controller"
  chart      = "./compute_plane/charts/aws-load-balancer-controller"
  #repository = "https://aws.github.io/eks-charts"
  namespace  = "kube-system"

  set {
    name  = "image.repository"
    value = "602401143452.dkr.ecr.${var.region}.amazonaws.com/amazon/aws-load-balancer-controller"
  }

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  values = [
    file("compute_plane/alb-ingress-controller-conf.yaml")
  ]

  depends_on = [
    module.eks,
    module.eks.worker_iam_role_name,
    aws_iam_policy.alb_policy,
    aws_iam_role_policy_attachment.alb_policy_attach
  ]

  provisioner "local-exec" {
    when    = destroy
    command = "sleep 60"
  }

}
