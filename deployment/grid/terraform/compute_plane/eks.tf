# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = var.enable_private_subnet
  cluster_enabled_log_types       = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  vpc_id     = var.vpc_id
  subnet_ids = var.vpc_private_subnet_ids

  # Node IAM Role  
  create_iam_role = true
  iam_role_additional_policies = {
    AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    eks_pull_through_cache_permission  = aws_iam_policy.eks_pull_through_cache_permission.arn
  }

  # EKS Managed Node Group(s)
  eks_managed_node_group_defaults = {
    ami_type                              = "AL2_x86_64"
    instance_types                        = ["m6i.xlarge", "m6id.xlarge", "m6a.xlarge", "m6in.xlarge", "m5.xlarge", "m5d.xlarge", "m5a.xlarge", "m5ad.xlarge", "m5n.xlarge"]
    attach_cluster_primary_security_group = false
  }

  eks_managed_node_groups = local.eks_worker_group_map

  # create_node_security_group    = true
  node_security_group_additional_rules = {
    # Extend node-to-node security group rules. Recommended and required for the Add-ons
    ingress_keda_apiservice = {
      description = "apiservice for Keda"
      type        = "ingress"
      self        = true
      from_port   = 9666
      to_port     = 9666
      protocol    = "tcp"
    }
    ingress_dns_tcp = {
      description = "Node to node DNS(TCP)"
      protocol    = "tcp"
      from_port   = 53
      to_port     = 53
      type        = "ingress"
      cidr_blocks = [var.vpc_cidr]
    }
    ingress_influxdb_tcp = {
      description = "Node to node influxdb"
      protocol    = "tcp"
      from_port   = 8086
      to_port     = 8088
      type        = "ingress"
      cidr_blocks = [var.vpc_cidr]
    }
    ingress_dns_udp = {
      description = "Node to node DNS(UDP)"
      protocol    = "udp"
      from_port   = 53
      to_port     = 53
      type        = "ingress"
      cidr_blocks = [var.vpc_cidr]
    }

    egress_dns_tcp = {
      description = "Node to node DNS(TCP)"
      protocol    = "tcp"
      from_port   = 53
      to_port     = 53
      type        = "egress"
      cidr_blocks = [var.vpc_cidr]
    }
    egress_dns_udp = {
      description = "Node to node DNS(UDP)"
      protocol    = "udp"
      from_port   = 53
      to_port     = 53
      type        = "egress"
      cidr_blocks = [var.vpc_cidr]
    }

    # Allow Control Plane Nodes to talk to Worker nodes on all ports. Added this to simplify the example and further avoid issues with Add-ons communication with Control plane.
    # This can be restricted further to specific port based on the requirement for each Add-on e.g., metrics-server 4443, spark-operator 8080, karpenter 8443 etc.
    # Change this according to your security requirements if needed
    ingress_cluster_to_node_all_traffic = {
      description                   = "Cluster API to Nodegroup all traffic"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }
    # Recommended outbound traffic for Node groups
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  # aws-auth configmap
  manage_aws_auth_configmap = true
  aws_auth_roles = concat(var.input_role, [
    {
      rolearn  = aws_iam_role.role_lambda_drainer.arn
      username = "lambda"
      groups   = ["system:masters"]
    }
  ])
}


module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.0"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  # EKS Managed Addons
  eks_addons = {
    coredns = {
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "PRESERVE"
      preserve                    = false
      most_recent                 = true
      configuration_values = jsonencode(
        {
          replicaCount : 2,
          nodeSelector : {
            "htc/node-type" : "core"
          },
          tolerations : [
            {
              key : "htc/node-type",
              operator : "Equal",
              value : "core",
              effect : "NoSchedule"
            }
          ]
        }
      )

      timeouts = {
        create = "5m"
        delete = "5m"
      }
    }

    kube-proxy = {
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "PRESERVE"
      most_recent                 = true
    }

    vpc-cni = {
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "PRESERVE"
      most_recent                 = true
    }
  }

  # AWS EKS Addons
  enable_aws_for_fluentbit = true
  aws_for_fluentbit_cw_log_group = {
    create    = true
    retention = 30
  }
  aws_for_fluentbit = {
    name             = "aws-for-fluent-bit"
    namespace        = "fluentbit"
    create_namespace = true
    chart_version    = "0.1.23"
    values = [templatefile("${path.module}/../../charts/values/aws-for-fluentbit.yaml", {
      aws_htc_ecr = var.aws_htc_ecr
      region      = var.region
    })]
  }

  enable_cluster_autoscaler = true
  cluster_autoscaler = {
    name          = "cluster-autoscaler"
    chart_version = "9.29.0"
    repository    = "https://kubernetes.github.io/autoscaler"
    namespace     = "kube-system"
    values = [templatefile("${path.module}/../../charts/values/cluster-autoscaler.yaml", {
      aws_htc_ecr    = var.aws_htc_ecr
      cluster_name   = module.eks.cluster_name
      region         = var.region
      k8s_ca_version = var.k8s_ca_version
    })]
  }

  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    values = [templatefile("${path.module}/../../charts/values/aws-alb-controller.yaml", {
      region = var.region
      vpc_id = var.vpc_id
    })]
  }

  enable_aws_cloudwatch_metrics = true
  aws_cloudwatch_metrics = {
    name          = "aws-cloudwatch-metrics"
    repository    = "https://aws.github.io/eks-charts"
    chart_version = "0.0.9"
    namespace     = "amazon-cloudwatch"
    values = [
      templatefile("${path.module}/../../charts/values/aws-cloudwatch-metrics.yaml", {
        aws_htc_ecr = var.aws_htc_ecr
      })
    ]
  }

  # Helm Release Addons
  helm_releases = {
    keda = {
      description      = "A Helm chart for KEDA"
      namespace        = "keda"
      create_namespace = true
      chart            = "keda"
      chart_version    = var.k8s_keda_version
      repository       = "https://kedacore.github.io/charts"
      values = [templatefile("${path.module}/../../charts/values/keda.yaml", {
        aws_htc_ecr      = var.aws_htc_ecr
        k8s_keda_version = var.k8s_keda_version
      })]
    }
    influxdb = {
      description      = "A Helm chart for InfluxDB"
      namespace        = "influxdb"
      create_namespace = true
      chart            = "influxdb"
      chart_version    = "4.10.4"
      repository       = "https://helm.influxdata.com/"
      values = [templatefile("${path.module}/../../charts/values/influxdb.yaml", {
        aws_htc_ecr = var.aws_htc_ecr
      })]
    }
    prometheus = {
      description      = "A Helm chart for Prometheus"
      namespace        = "prometheus"
      create_namespace = true
      chart            = "prometheus"
      chart_version    = "15.17.0"
      repository       = "https://prometheus-community.github.io/helm-charts"
      values = [templatefile("${path.module}/../../charts/values/prometheus.yaml", {
        aws_htc_ecr            = var.aws_htc_ecr
        region                 = var.region
        kube_state_metrics_tag = var.prometheus_configuration.kube_state_metrics_tag
        configmap_reload_tag   = var.prometheus_configuration.configmap_reload_tag
      })]
    }
    grafana = {
      description      = "A Helm chart for Grafana"
      namespace        = "grafana"
      create_namespace = true
      chart            = "grafana"
      chart_version    = "6.43.1"
      repository       = "https://grafana.github.io/helm-charts"
      values = [templatefile("${path.module}/../../charts/values/grafana.yaml", {
        aws_htc_ecr                                       = var.aws_htc_ecr
        k8s_keda_version                                  = var.k8s_keda_version
        grafana_configuration_initChownData_tag           = var.grafana_configuration.initChownData_tag
        grafana_configuration_grafana_tag                 = var.grafana_configuration.grafana_tag
        grafana_configuration_downloadDashboardsImage_tag = var.grafana_configuration.downloadDashboardsImage_tag
        grafana_configuration_sidecar_tag                 = var.grafana_configuration.sidecar_tag
        grafana_configuration_admin_password              = var.grafana_configuration.admin_password
        alb_certificate_arn                               = aws_iam_server_certificate.alb_certificate.arn
        vpc_public_subnets                                = join(",", var.vpc_public_subnet_ids)
        htc_metrics_dashboard_json                        = indent(8, file("${path.module}/files/htc-dashboard.json"))
        kubernetes_metrics_dashboard_json                 = indent(8, file("${path.module}/files/kubernetes-dashboard.json"))
      })]
    }
  }
}


resource "null_resource" "update_kubeconfig" {
  triggers = {
    cluster_arn = module.eks.cluster_arn
  }

  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name}"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "kubectl config delete-cluster ${self.triggers.cluster_arn}"
  }
}
