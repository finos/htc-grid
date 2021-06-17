# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

resource "kubernetes_namespace" "ssm_installer" {
  metadata {
    name = "ssm-installer"
  }
  depends_on = [module.eks]
}

resource "kubernetes_daemonset" "ssm_installer" {
  metadata {
    name      = "ssm-installer"
    namespace = "ssm-installer"

    labels = {
      k8s-app = "ssm-installer"
    }
  }

  spec {
    selector {
      match_labels = {
        k8s-app = "ssm-installer"
      }
    }

    template {
      metadata {
        labels = {
          k8s-app = "ssm-installer"
        }
      }

      spec {
        volume {
          name = "cronfile"

          host_path {
            path = "/etc/cron.d"
            type = "Directory"
          }
        }

        container {
          name    = "ssm"
          image   = "${var.aws_htc_ecr}/amazonlinux:latest"
          command = ["/bin/bash"]
          args    = ["-c", "echo '* * * * * root yum install -y https://s3.${var.region}.amazonaws.com/amazon-ssm-${var.region}/latest/linux_amd64/amazon-ssm-agent.rpm & rm -rf /etc/cron.d/ssmstart' > /etc/cron.d/ssmstart; while true; do sleep 3600; done"]

          volume_mount {
            name       = "cronfile"
            mount_path = "/etc/cron.d"
          }

          termination_message_path = "/dev/termination-log"
          image_pull_policy        = "Always"

          security_context {
            allow_privilege_escalation = true
          }
        }

        restart_policy                   = "Always"
        termination_grace_period_seconds = 30
        dns_policy                       = "ClusterFirst"

        toleration {
          key      = "grid/type"
          operator = "Equal"
          value    = "Operator"
          effect   = "NoSchedule"
        }
      }
    }
  }
  depends_on = [kubernetes_namespace.ssm_installer]
}

