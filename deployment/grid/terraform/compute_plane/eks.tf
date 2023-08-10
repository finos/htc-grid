# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


locals {
  chart_version = {
    aws_for_fluentbit      = "0.1.28"
    aws_cloudwatch_metrics = "0.0.9"
    cluster_autoscaler     = "9.29.1"
    keda                   = try(var.k8s_keda_version, "2.11.2")
    influxdb               = "4.12.3"
    prometheus             = "23.3.0"
    grafana                = "6.58.8"
  }
}


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
        create = "1m"
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
  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    values = [templatefile("${path.module}/../../charts/values/aws-alb-controller.yaml", {
      aws_htc_ecr = var.aws_htc_ecr
      region      = var.region
      vpc_id      = var.vpc_id
    })]
  }

  enable_aws_for_fluentbit = true
  aws_for_fluentbit_cw_log_group = {
    create    = true
    retention = 30
  }
  aws_for_fluentbit = {
    name             = "aws-for-fluent-bit"
    namespace        = "fluentbit"
    create_namespace = true
    chart_version    = local.chart_version.aws_for_fluentbit
    values = [templatefile("${path.module}/../../charts/values/aws-for-fluentbit.yaml", {
      aws_htc_ecr = var.aws_htc_ecr
      region      = var.region
    })]
  }

  enable_aws_cloudwatch_metrics = true
  aws_cloudwatch_metrics = {
    name          = "aws-cloudwatch-metrics"
    repository    = "https://aws.github.io/eks-charts"
    chart_version = local.chart_version.aws_cloudwatch_metrics
    namespace     = "amazon-cloudwatch"
    values = [templatefile("${path.module}/../../charts/values/aws-cloudwatch-metrics.yaml", {
      aws_htc_ecr = var.aws_htc_ecr
      })
    ]
  }

  enable_cluster_autoscaler = true
  cluster_autoscaler = {
    name          = "cluster-autoscaler"
    chart_version = local.chart_version.cluster_autoscaler
    repository    = "https://kubernetes.github.io/autoscaler"
    namespace     = "kube-system"
    values = [templatefile("${path.module}/../../charts/values/cluster-autoscaler.yaml", {
      aws_htc_ecr    = var.aws_htc_ecr
      cluster_name   = module.eks.cluster_name
      region         = var.region
      k8s_ca_version = var.k8s_ca_version
    })]
  }

  # Helm Release Addons
  helm_releases = {
    keda = {
      description      = "A Helm chart for KEDA"
      namespace        = "keda"
      create_namespace = true
      chart            = "keda"
      chart_version    = local.chart_version.keda
      repository       = "https://kedacore.github.io/charts"
      values = [templatefile("${path.module}/../../charts/values/keda.yaml", {
        aws_htc_ecr = var.aws_htc_ecr
      })]
    }
    influxdb = {
      description      = "A Helm chart for InfluxDB"
      namespace        = "influxdb"
      create_namespace = true
      chart            = "influxdb"
      chart_version    = local.chart_version.influxdb
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
      chart_version    = local.chart_version.prometheus
      repository       = "https://prometheus-community.github.io/helm-charts"
      values = [templatefile("${path.module}/../../charts/values/prometheus.yaml", {
        aws_htc_ecr = var.aws_htc_ecr
        region      = var.region
      })]
    }
    grafana = {
      description      = "A Helm chart for Grafana"
      namespace        = "grafana"
      create_namespace = true
      chart            = "grafana"
      chart_version    = local.chart_version.grafana
      repository       = "https://grafana.github.io/helm-charts"
      values = [templatefile("${path.module}/../../charts/values/grafana.yaml", {
        aws_htc_ecr                          = var.aws_htc_ecr
        grafana_configuration_admin_password = var.grafana_configuration.admin_password
        alb_certificate_arn                  = aws_acm_certificate.alb_certificate.arn
        vpc_public_subnets                   = join(",", var.vpc_public_subnet_ids)
        htc_metrics_dashboard_json           = indent(8, file("${path.module}/files/htc-dashboard.json"))
        kubernetes_metrics_dashboard_json    = indent(8, file("${path.module}/files/kubernetes-dashboard.json"))
      })]
    }
  }
}


# Due to the fact that EKS Blueprint Addons don't declare a dependency between Helm and ie AWS LoadBalancer Controller, there can be an edge case where on
# destroy, the LB Controller may be removed before it has cleaned up the AWS resources that it created, ie ALBs and SGs. This results in orphaned resources
# that then block the end-to-end destroy of ie the VPC. The resource below are used to create an implicit dependency between the Helm addons and the external
# AWS resources created by the AWS LoadBalancer Controller and ensuring they are cleaned up in order. Once this is fixed in the upstream modules or components
# (via a TF dependency or a finalizer), these will be removed and all of the chart resources will be managed via Helm.


# This resource is used to create an implicit dependency between the EKS Addons and the AWS External resources
resource "time_sleep" "this" {
  # Giving EKS some time to create the Helm resources
  create_duration = "10s"

  triggers = {
    grafana_namespace     = module.eks_blueprints_addons.helm_releases["grafana"].namespace
    grafana_release_name  = module.eks_blueprints_addons.helm_releases["grafana"].name
    influxdb_namespace    = module.eks_blueprints_addons.helm_releases["influxdb"].namespace
    influxdb_release_name = module.eks_blueprints_addons.helm_releases["influxdb"].name
  }

  depends_on = [
    module.eks,
    module.eks_blueprints_addons,
    null_resource.update_kubeconfig
  ]
}


# These null_resoures are used to ensure the external resources are deleted, by ie removing the annotations/resources, and allowing the LB COntroller to
# cleanup the external resources before the EKS Addons are destroyed.
resource "null_resource" "destroy_external_influxdb_lb" {
  triggers = {
    influxdb_namespace    = time_sleep.this.triggers["influxdb_namespace"]
    influxdb_release_name = time_sleep.this.triggers["influxdb_release_name"]
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      # Change the service type to ClusterIP which should cause LB Controller to remove external resources
      if kubectl -n ${self.triggers.influxdb_namespace} get service ${self.triggers.influxdb_release_name} > /dev/null 2>&1; then
        kubectl -n ${self.triggers.influxdb_namespace} patch service ${self.triggers.influxdb_release_name} \
          --type='json' -p '[{"op":"replace","path":"/spec/type","value":"ClusterIP"}]'
      fi

      # Give some time to the AWS LB Controller to reconcile and delete the external resources
      sleep 10
    EOT
  }
}


resource "null_resource" "destroy_external_grafana_lb" {
  triggers = {
    grafana_namespace    = time_sleep.this.triggers["grafana_namespace"]
    grafana_release_name = time_sleep.this.triggers["grafana_release_name"]
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      # Delete the ingress annotations which should cause LB Controller to remove external resources
      if kubectl -n ${self.triggers.grafana_namespace} get ingress ${self.triggers.grafana_release_name}  > /dev/null 2>&1; then
        kubectl -n ${self.triggers.grafana_namespace} annotate ingress ${self.triggers.grafana_release_name} \
          kubernetes.io/ingress.class- \
          alb.ingress.kubernetes.io/scheme- alb.ingress.kubernetes.io/listen-ports- \
          alb.ingress.kubernetes.io/certificate-arn- alb.ingress.kubernetes.io/subnets- \
          alb.ingress.kubernetes.io/actions.ssl-redirect-
      fi

      # Give some time to the AWS LB Controller to reconcile and delete the external resources
      sleep 10
    EOT
  }
}


# This null_resource is used to update the local kubeconfig allowing for running kubectl commands
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
