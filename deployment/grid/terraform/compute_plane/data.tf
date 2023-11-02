# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


# These resources are used to give AWS Load Balancer Controller time to create
# and delete the external AWS resources, i.e. ALB, NLB and Target Groups
resource "time_sleep" "influxdb_service_dependency" {
  # Giving EKS some time to create/delete the NLB Resources
  create_duration = "10s"

  triggers = {
    name      = helm_release.this["influxdb"].name
    namespace = helm_release.this["influxdb"].namespace
  }
}


resource "time_sleep" "grafana_ingress_dependency" {
  # Giving EKS some time to create/delete the ALB resources
  create_duration = "10s"

  triggers = {
    name      = helm_release.this["grafana"].name
    namespace = helm_release.this["grafana"].namespace
  }
}


data "kubernetes_service_v1" "influxdb_load_balancer" {
  metadata {
    name      = time_sleep.influxdb_service_dependency.triggers["name"]
    namespace = time_sleep.influxdb_service_dependency.triggers["namespace"]
  }
}


data "kubernetes_ingress_v1" "grafana_ingress" {
  metadata {
    name      = time_sleep.grafana_ingress_dependency.triggers["name"]
    namespace = time_sleep.grafana_ingress_dependency.triggers["namespace"]
  }
}


# Retrieve the account ID
data "aws_caller_identity" "current" {}


# Retrieve AWS Partition
data "aws_partition" "current" {}
