# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

resource "kubernetes_cluster_role" "lambda_cluster_access" {
  metadata {
    name = "lambda-cluster-access"
  }

  rule {
    verbs      = ["create", "list", "patch"]
    api_groups = [""]
    resources  = ["pods", "pods/eviction", "nodes"]
  }
  depends_on = [
      module.eks
  ]
}

resource "kubernetes_cluster_role_binding" "lambda_user_cluster_role_binding" {
  metadata {
    name = "lambda-user-cluster-role-binding"
  }

  subject {
    kind = "User"
    name = "lambda"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "lambda-cluster-access"
  }
  depends_on = [
      module.eks
  ]
}

