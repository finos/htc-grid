# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

resource "kubernetes_namespace" "amazon_cloudwatch" {
  metadata {
    name = "amazon-cloudwatch"

    labels = {
      name = "amazon-cloudwatch"
    }
  }
}

resource "kubernetes_service_account" "cloudwatch_agent" {
  metadata {
    name      = "cloudwatch-agent"
    namespace = "amazon-cloudwatch"
  }
  automount_service_account_token = true

  depends_on = [
    kubernetes_namespace.amazon_cloudwatch
  ]
}

resource "kubernetes_cluster_role" "cloudwatch_agent_role" {
  metadata {
    name = "cloudwatch-agent-role"
  }

  rule {
    verbs      = ["list", "watch"]
    api_groups = [""]
    resources  = ["pods", "nodes", "endpoints"]
  }

  rule {
    verbs      = ["list", "watch"]
    api_groups = ["apps"]
    resources  = ["replicasets"]
  }

  rule {
    verbs      = ["list", "watch"]
    api_groups = ["batch"]
    resources  = ["jobs"]
  }

  rule {
    verbs      = ["get"]
    api_groups = [""]
    resources  = ["nodes/proxy"]
  }

  rule {
    verbs      = ["create"]
    api_groups = [""]
    resources  = ["nodes/stats", "configmaps", "events"]
  }

  rule {
    verbs          = ["get", "update"]
    api_groups     = [""]
    resources      = ["configmaps"]
    resource_names = ["cwagent-clusterleader"]
  }
  depends_on = [
    kubernetes_namespace.amazon_cloudwatch
  ]
}

resource "kubernetes_cluster_role_binding" "cloudwatch_agent_role_binding" {
  metadata {
    name = "cloudwatch-agent-role-binding"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "cloudwatch-agent"
    namespace = "amazon-cloudwatch"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cloudwatch-agent-role"
  }
  depends_on = [
    kubernetes_namespace.amazon_cloudwatch
  ]
}

resource "kubernetes_config_map" "cwagentconfig" {
  metadata {
    name      = "cwagentconfig"
    namespace = "amazon-cloudwatch"
  }

  data = {
    "cwagentconfig.json" = "{\n  \"agent\": {\n    \"region\": \"${var.region}\"\n  },\n  \"logs\": {\n    \"metrics_collected\": {\n      \"kubernetes\": {\n        \"cluster_name\": \"${var.cluster_name}\",\n        \"metrics_collection_interval\": 60\n      }\n    },\n    \"force_flush_interval\": 5\n  }\n}\n"
  }
  depends_on = [
    kubernetes_namespace.amazon_cloudwatch
  ]
}

resource "kubernetes_daemonset" "cloudwatch_agent" {
  metadata {
    name      = "cloudwatch-agent"
    namespace = "amazon-cloudwatch"
  }

  spec {
    selector {
      match_labels = {
        name = "cloudwatch-agent"
      }
    }

    template {
      metadata {
        labels = {
          name = "cloudwatch-agent"
        }
      }

      spec {
        volume {
          name = "cwagentconfig"

          config_map {
            name = "cwagentconfig"
          }
        }

        volume {
          name = "rootfs"

          host_path {
            path = "/"
          }
        }

        volume {
          name = "dockersock"

          host_path {
            path = "/var/run/docker.sock"
          }
        }

        volume {
          name = "varlibdocker"

          host_path {
            path = "/var/lib/docker"
          }
        }

        volume {
          name = "sys"

          host_path {
            path = "/sys"
          }
        }

        volume {
          name = "devdisk"

          host_path {
            path = "/dev/disk/"
          }
        }

        container {
          name  = "cloudwatch-agent"
          image = "${var.aws_htc_ecr}/amazon/cloudwatch-agent:${var.cw_agent_version}"

          env {
            name = "HOST_IP"

            value_from {
              field_ref {
                field_path = "status.hostIP"
              }
            }
          }

          env {
            name = "HOST_NAME"

            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }

          env {
            name = "K8S_NAMESPACE"

            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }

          env {
            name  = "CI_VERSION"
            value = "k8s/1.3.5"
          }

          resources {
            limits = {
              cpu    = "200m"
              memory = "200Mi"
            }

            requests = {
              memory = "200Mi"
              cpu    = "200m"
            }
          }

          volume_mount {
            name       = "cwagentconfig"
            mount_path = "/etc/cwagentconfig"
          }

          volume_mount {
            name       = "rootfs"
            read_only  = true
            mount_path = "/rootfs"
          }

          volume_mount {
            name       = "dockersock"
            read_only  = true
            mount_path = "/var/run/docker.sock"
          }

          volume_mount {
            name       = "varlibdocker"
            read_only  = true
            mount_path = "/var/lib/docker"
          }

          volume_mount {
            name       = "sys"
            read_only  = true
            mount_path = "/sys"
          }

          volume_mount {
            name       = "devdisk"
            read_only  = true
            mount_path = "/dev/disk"
          }

          volume_mount {
            name = kubernetes_service_account.cloudwatch_agent.default_secret_name
            read_only = true
            mount_path = "/var/run/secrets/kubernetes.io/serviceaccount"
          }
        }

        volume {
          name = kubernetes_service_account.cloudwatch_agent.default_secret_name
          secret {
            secret_name = kubernetes_service_account.cloudwatch_agent.default_secret_name
          }
        }

        termination_grace_period_seconds = 60
        service_account_name             = "cloudwatch-agent"
      }
    }
  }
  depends_on = [
    kubernetes_namespace.amazon_cloudwatch
  ]
}

resource "kubernetes_config_map" "fluent_bit_cluster_info" {
  metadata {
    name      = "fluent-bit-cluster-info"
    namespace = "amazon-cloudwatch"
  }

  data = {
    "cluster.name" = var.cluster_name

    "http.port" = "2020"

    "http.server" = "On"

    "logs.region" = var.region

    "read.head" = "Off"

    "read.tail" = "On"
  }
  depends_on = [
    kubernetes_namespace.amazon_cloudwatch
  ]
}

resource "kubernetes_service_account" "fluent_bit" {
  metadata {
    name      = "fluent-bit"
    namespace = "amazon-cloudwatch"
  }
  automount_service_account_token = true
  depends_on = [
    kubernetes_namespace.amazon_cloudwatch
  ]
}

resource "kubernetes_cluster_role" "fluent_bit_role" {
  metadata {
    name = "fluent-bit-role"
  }

  rule {
    verbs             = ["get"]
    non_resource_urls = ["/metrics"]
  }

  rule {
    verbs      = ["get", "list", "watch"]
    api_groups = [""]
    resources  = ["namespaces", "pods", "pods/logs"]
  }
  depends_on = [
    kubernetes_namespace.amazon_cloudwatch
  ]
}

resource "kubernetes_cluster_role_binding" "fluent_bit_role_binding" {
  metadata {
    name = "fluent-bit-role-binding"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "fluent-bit"
    namespace = "amazon-cloudwatch"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "fluent-bit-role"
  }
  depends_on = [
    kubernetes_namespace.amazon_cloudwatch
  ]
}

resource "kubernetes_config_map" "fluent_bit_config" {
  metadata {
    name      = "fluent-bit-config"
    namespace = "amazon-cloudwatch"

    labels = {
      k8s-app = "fluent-bit"
    }
  }

  data = {
    "application-log.conf" = "[INPUT]\n    Name                tail\n    Tag                 application.*\n    Exclude_Path        /var/log/containers/cloudwatch-agent*, /var/log/containers/fluent-bit*, /var/log/containers/aws-node*, /var/log/containers/kube-proxy*\n    Path                /var/log/containers/*.log\n    Docker_Mode         On\n    Docker_Mode_Flush   5\n    Docker_Mode_Parser  container_firstline\n    Parser              docker\n    DB                  /var/fluent-bit/state/flb_container.db\n    Mem_Buf_Limit       50MB\n    Skip_Long_Lines     On\n    Refresh_Interval    10\n    Rotate_Wait         30\n    storage.type        filesystem\n    Read_from_Head      $${READ_FROM_HEAD}\n\n[INPUT]\n    Name                tail\n    Tag                 application.*\n    Path                /var/log/containers/fluent-bit*\n    Parser              docker\n    DB                  /var/fluent-bit/state/flb_log.db\n    Mem_Buf_Limit       5MB\n    Skip_Long_Lines     On\n    Refresh_Interval    10\n    Read_from_Head      $${READ_FROM_HEAD}\n\n[INPUT]\n    Name                tail\n    Tag                 application.*\n    Path                /var/log/containers/cloudwatch-agent*\n    Docker_Mode         On\n    Docker_Mode_Flush   5\n    Docker_Mode_Parser  cwagent_firstline\n    Parser              docker\n    DB                  /var/fluent-bit/state/flb_cwagent.db\n    Mem_Buf_Limit       5MB\n    Skip_Long_Lines     On\n    Refresh_Interval    10\n    Read_from_Head      $${READ_FROM_HEAD}\n\n[FILTER]\n    Name                kubernetes\n    Match               application.*\n    Kube_URL            https://kubernetes.default.svc:443\n    Kube_Tag_Prefix     application.var.log.containers.\n    Merge_Log           On\n    Merge_Log_Key       log_processed\n    K8S-Logging.Parser  On\n    K8S-Logging.Exclude Off\n    Labels              Off\n    Annotations         Off\n\n[OUTPUT]\n    Name                cloudwatch_logs\n    Match               application.*\n    region              $${AWS_REGION}\n    log_group_name      /aws/containerinsights/$${CLUSTER_NAME}/application\n    log_stream_prefix   $${HOST_NAME}-\n    auto_create_group   true\n    extra_user_agent    container-insights\n"

    "dataplane-log.conf" = "[INPUT]\n    Name                systemd\n    Tag                 dataplane.systemd.*\n    Systemd_Filter      _SYSTEMD_UNIT=docker.service\n    DB                  /var/fluent-bit/state/systemd.db\n    Path                /var/log/journal\n    Read_From_Tail      $${READ_FROM_TAIL}\n\n[INPUT]\n    Name                tail\n    Tag                 dataplane.tail.*\n    Path                /var/log/containers/aws-node*, /var/log/containers/kube-proxy*\n    Docker_Mode         On\n    Docker_Mode_Flush   5\n    Docker_Mode_Parser  container_firstline\n    Parser              docker\n    DB                  /var/fluent-bit/state/flb_dataplane_tail.db\n    Mem_Buf_Limit       50MB\n    Skip_Long_Lines     On\n    Refresh_Interval    10\n    Rotate_Wait         30\n    storage.type        filesystem\n    Read_from_Head      $${READ_FROM_HEAD}\n\n[FILTER]\n    Name                modify\n    Match               dataplane.systemd.*\n    Rename              _HOSTNAME                   hostname\n    Rename              _SYSTEMD_UNIT               systemd_unit\n    Rename              MESSAGE                     message\n    Remove_regex        ^((?!hostname|systemd_unit|message).)*$\n\n[FILTER]\n    Name                aws\n    Match               dataplane.*\n    imds_version        v1\n\n[OUTPUT]\n    Name                cloudwatch_logs\n    Match               dataplane.*\n    region              $${AWS_REGION}\n    log_group_name      /aws/containerinsights/$${CLUSTER_NAME}/dataplane\n    log_stream_prefix   $${HOST_NAME}-\n    auto_create_group   true\n    extra_user_agent    container-insights\n"

    "fluent-bit.conf" = "[SERVICE]\n    Flush                     5\n    Log_Level                 info\n    Daemon                    off\n    Parsers_File              parsers.conf\n    HTTP_Server               $${HTTP_SERVER}\n    HTTP_Listen               0.0.0.0\n    HTTP_Port                 $${HTTP_PORT}\n    storage.path              /var/fluent-bit/state/flb-storage/\n    storage.sync              normal\n    storage.checksum          off\n    storage.backlog.mem_limit 5M\n    \n@INCLUDE application-log.conf\n@INCLUDE dataplane-log.conf\n@INCLUDE host-log.conf\n"

    "host-log.conf" = "[INPUT]\n    Name                tail\n    Tag                 host.dmesg\n    Path                /var/log/dmesg\n    Parser              syslog\n    DB                  /var/fluent-bit/state/flb_dmesg.db\n    Mem_Buf_Limit       5MB\n    Skip_Long_Lines     On\n    Refresh_Interval    10\n    Read_from_Head      $${READ_FROM_HEAD}\n\n[INPUT]\n    Name                tail\n    Tag                 host.messages\n    Path                /var/log/messages\n    Parser              syslog\n    DB                  /var/fluent-bit/state/flb_messages.db\n    Mem_Buf_Limit       5MB\n    Skip_Long_Lines     On\n    Refresh_Interval    10\n    Read_from_Head      $${READ_FROM_HEAD}\n\n[INPUT]\n    Name                tail\n    Tag                 host.secure\n    Path                /var/log/secure\n    Parser              syslog\n    DB                  /var/fluent-bit/state/flb_secure.db\n    Mem_Buf_Limit       5MB\n    Skip_Long_Lines     On\n    Refresh_Interval    10\n    Read_from_Head      $${READ_FROM_HEAD}\n\n[FILTER]\n    Name                aws\n    Match               host.*\n    imds_version        v1\n\n[OUTPUT]\n    Name                cloudwatch_logs\n    Match               host.*\n    region              $${AWS_REGION}\n    log_group_name      /aws/containerinsights/$${CLUSTER_NAME}/host\n    log_stream_prefix   $${HOST_NAME}.\n    auto_create_group   true\n    extra_user_agent    container-insights\n"

    "parsers.conf" = "[PARSER]\n    Name                docker\n    Format              json\n    Time_Key            time\n    Time_Format         %Y-%m-%dT%H:%M:%S.%LZ\n\n[PARSER]\n    Name                syslog\n    Format              regex\n    Regex               ^(?<time>[^ ]* {1,2}[^ ]* [^ ]*) (?<host>[^ ]*) (?<ident>[a-zA-Z0-9_\\/\\.\\-]*)(?:\\[(?<pid>[0-9]+)\\])?(?:[^\\:]*\\:)? *(?<message>.*)$\n    Time_Key            time\n    Time_Format         %b %d %H:%M:%S\n\n[PARSER]\n    Name                container_firstline\n    Format              regex\n    Regex               (?<log>(?<=\"log\":\")\\S(?!\\.).*?)(?<!\\\\)\".*(?<stream>(?<=\"stream\":\").*?)\".*(?<time>\\d{4}-\\d{1,2}-\\d{1,2}T\\d{2}:\\d{2}:\\d{2}\\.\\w*).*(?=})\n    Time_Key            time\n    Time_Format         %Y-%m-%dT%H:%M:%S.%LZ\n\n[PARSER]\n    Name                cwagent_firstline\n    Format              regex\n    Regex               (?<log>(?<=\"log\":\")\\d{4}[\\/-]\\d{1,2}[\\/-]\\d{1,2}[ T]\\d{2}:\\d{2}:\\d{2}(?!\\.).*?)(?<!\\\\)\".*(?<stream>(?<=\"stream\":\").*?)\".*(?<time>\\d{4}-\\d{1,2}-\\d{1,2}T\\d{2}:\\d{2}:\\d{2}\\.\\w*).*(?=})\n    Time_Key            time\n    Time_Format         %Y-%m-%dT%H:%M:%S.%LZ\n"
  }
  depends_on = [
    kubernetes_namespace.amazon_cloudwatch
  ]
}

resource "kubernetes_daemonset" "fluent_bit" {
  metadata {
    name      = "fluent-bit"
    namespace = "amazon-cloudwatch"

    labels = {
      k8s-app = "fluent-bit"

      "kubernetes.io/cluster-service" = "true"

      version = "v1"
    }
  }

  spec {
    selector {
      match_labels = {
        k8s-app = "fluent-bit"
      }
    }

    template {
      metadata {
        labels = {
          k8s-app = "fluent-bit"

          "kubernetes.io/cluster-service" = "true"

          version = "v1"
        }
      }

      spec {
        volume {
          name = "fluentbitstate"

          host_path {
            path = "/var/fluent-bit/state"
          }
        }

        volume {
          name = "varlog"

          host_path {
            path = "/var/log"
          }
        }

        volume {
          name = "varlibdockercontainers"

          host_path {
            path = "/var/lib/docker/containers"
          }
        }

        volume {
          name = "fluent-bit-config"

          config_map {
            name = "fluent-bit-config"
          }
        }

        volume {
          name = "runlogjournal"

          host_path {
            path = "/run/log/journal"
          }
        }

        volume {
          name = "dmesg"

          host_path {
            path = "/var/log/dmesg"
          }
        }

        container {
          name  = "fluent-bit"
          image = "${var.aws_htc_ecr}/aws-for-fluent-bit:${var.fluentbit_version}"

          env {
            name = "AWS_REGION"

            value_from {
              config_map_key_ref {
                name = "fluent-bit-cluster-info"
                key  = "logs.region"
              }
            }
          }

          env {
            name = "CLUSTER_NAME"

            value_from {
              config_map_key_ref {
                name = "fluent-bit-cluster-info"
                key  = "cluster.name"
              }
            }
          }

          env {
            name = "HTTP_SERVER"

            value_from {
              config_map_key_ref {
                name = "fluent-bit-cluster-info"
                key  = "http.server"
              }
            }
          }

          env {
            name = "HTTP_PORT"

            value_from {
              config_map_key_ref {
                name = "fluent-bit-cluster-info"
                key  = "http.port"
              }
            }
          }

          env {
            name = "READ_FROM_HEAD"

            value_from {
              config_map_key_ref {
                name = "fluent-bit-cluster-info"
                key  = "read.head"
              }
            }
          }

          env {
            name = "READ_FROM_TAIL"

            value_from {
              config_map_key_ref {
                name = "fluent-bit-cluster-info"
                key  = "read.tail"
              }
            }
          }

          env {
            name = "HOST_NAME"

            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }

          env {
            name  = "CI_VERSION"
            value = "k8s/1.3.5"
          }

          resources {
            limits = {
              memory = "200Mi"
            }

            requests = {
              cpu    = "500m"
              memory = "100Mi"
            }
          }

          volume_mount {
            name       = "fluentbitstate"
            mount_path = "/var/fluent-bit/state"
          }

          volume_mount {
            name       = "varlog"
            read_only  = true
            mount_path = "/var/log"
          }

          volume_mount {
            name       = "varlibdockercontainers"
            read_only  = true
            mount_path = "/var/lib/docker/containers"
          }

          volume_mount {
            name       = "fluent-bit-config"
            mount_path = "/fluent-bit/etc/"
          }

          volume_mount {
            name       = "runlogjournal"
            read_only  = true
            mount_path = "/run/log/journal"
          }

          volume_mount {
            name       = "dmesg"
            read_only  = true
            mount_path = "/var/log/dmesg"
          }

          volume_mount {
            name = kubernetes_service_account.fluent_bit.default_secret_name
            read_only = true
            mount_path = "/var/run/secrets/kubernetes.io/serviceaccount"
          }

          image_pull_policy = "Always"
        }

        volume {
          name = kubernetes_service_account.fluent_bit.default_secret_name
          secret {
            secret_name = kubernetes_service_account.fluent_bit.default_secret_name
          }
        }

        termination_grace_period_seconds = 10
        service_account_name             = "fluent-bit"

        toleration {
          key      = "node-role.kubernetes.io/master"
          operator = "Exists"
          effect   = "NoSchedule"
        }

        toleration {
          operator = "Exists"
          effect   = "NoExecute"
        }

        toleration {
          operator = "Exists"
          effect   = "NoSchedule"
        }
      }
    }
  }
  depends_on = [
    kubernetes_namespace.amazon_cloudwatch
  ]
}

