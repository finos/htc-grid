# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


data "kubernetes_service" "influxdb_load_balancer" {
  metadata {
    name      = "influxdb"
    namespace = "influxdb"
  }

  depends_on = [module.eks_blueprints_addons]
}


data "aws_caller_identity" "current" {}
