# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

resource "kubernetes_daemonset" "xray_daemon" {
  metadata {
    name      = "xray-daemon"
    namespace = "kube-system"
  }

  spec {
    selector {
      match_labels = {
        app = "xray-daemon"
      }
    }

    template {
      metadata {
        labels = {
          app = "xray-daemon"
        }
      }

      spec {
        volume {
          name = "config-volume"

          config_map {
            name = "xray-config"
          }
        }

        container {
          name    = "xray-daemon"
          image   = "${var.aws_htc_ecr}/aws-xray-daemon:${var.aws_xray_daemon_version}"
          command = ["/xray", "-c", "/aws/xray/config.yaml", "-l", "dev", "-t", "0.0.0.0:2000"]

          port {
            name           = "xray-ingest"
            host_port      = 2000
            container_port = 2000
            protocol       = "UDP"
          }

          port {
            name           = "xray-tcp"
            host_port      = 2000
            container_port = 2000
            protocol       = "TCP"
          }

          resources {
            limits = {
              cpu    = "512m"
              memory = "64Mi"
            }

            requests = {
              memory = "32Mi"
              cpu    = "256m"
            }
          }

          volume_mount {
            name       = "config-volume"
            read_only  = true
            mount_path = "/aws/xray"
          }
        }
      }
    }

    strategy {
      type = "RollingUpdate"
    }
  }
}

resource "kubernetes_config_map" "xray_config" {
  metadata {
    name      = "xray-config"
    namespace = "kube-system"
  }

  data = {
    "config.yaml" = "TotalBufferSizeMB: 24\nSocket:\n  UDPAddress: \"0.0.0.0:2000\"\n  TCPAddress: \"0.0.0.0:2000\"\nVersion: 2"
  }
}

resource "kubernetes_service" "xray_service" {
  metadata {
    name      = "xray-service"
    namespace = "kube-system"
  }

  spec {
    port {
      name     = "xray-ingest"
      protocol = "UDP"
      port     = 2000
    }

    port {
      name     = "xray-tcp"
      protocol = "TCP"
      port     = 2000
    }

    selector = {
      app = "xray-daemon"
    }

    cluster_ip = "None"
  }
}

