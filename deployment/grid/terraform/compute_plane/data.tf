# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


data "kubernetes_service_v1" "influxdb_load_balancer" {
  metadata {
    name      = time_sleep.influxdb_service_dependency.triggers["influxdb_release_name"]
    namespace = time_sleep.influxdb_service_dependency.triggers["influxdb_namespace"]
  }
}


data "kubernetes_ingress_v1" "grafana_ingress" {
  metadata {
    name      = time_sleep.grafana_ingress_dependency.triggers["grafana_release_name"]
    namespace = time_sleep.grafana_ingress_dependency.triggers["grafana_namespace"]
  }
}


# Retrieve the account ID
data "aws_caller_identity" "current" {}


# Retrieve AWS Partition
data "aws_partition" "current" {}
