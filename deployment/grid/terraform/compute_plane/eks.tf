# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


locals {
  chart_version = {
    aws_for_fluentbit      = "0.1.30"
    aws_cloudwatch_metrics = "0.0.9"
    cluster_autoscaler     = "9.29.3"
    keda                   = try(var.k8s_keda_version, "2.11.2")
    influxdb               = "4.12.5"
    prometheus             = "24.3.1"
    grafana                = "6.59.4"
  }
}


module "eks_cloudwatch_kms_key" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 2.0"

  description             = "CMK KMS Key used to encrypt EKS Cluster CloudWatch Logs"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true

  key_administrators = local.kms_key_admin_arns

  key_statements = [
    {
      sid = "Allow EKS to encrypt/decrypt CloudWatch Logs"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
        "kms:Decrypt",
      ]
      effect = "Allow"
      principals = [
        {
          type = "Service"
          identifiers = [
            "logs.${var.region}.${local.dns_suffix}"
          ]
        }
      ]
      resources = ["*"]
      conditions = [
        {
          test     = "ArnEquals"
          variable = "kms:EncryptionContext:aws:logs:arn"
          values   = ["arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:/aws/eks/${var.cluster_name}/cluster"]
        }
      ]
    }
  ]

  aliases = ["cloudwatch/eks/${var.cluster_name}"]
}

#trivy:ignore:AVD-AWS-0040 Allow Public EKS API Access
#trivy:ignore:AVD-AWS-0041 Allow API Access from 0.0.0.0/0
#trivy:ignore:AVD-AWS-0104 Allow ALL Egress CIDR ranges
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  cluster_endpoint_private_access = var.enable_private_subnet
  cluster_endpoint_public_access  = true
  # cluster_endpoint_public_access_cidrs = var.allowed_access_cidr_blocks

  create_kms_key                  = true
  enable_kms_key_rotation         = true
  kms_key_enable_default_policy   = true
  kms_key_description             = "CMK KMS Key used to encrypt/decrypt EKS Secrets"
  kms_key_deletion_window_in_days = var.kms_deletion_window
  kms_key_administrators          = local.kms_key_admin_arns

  create_cloudwatch_log_group     = true
  cloudwatch_log_group_kms_key_id = module.eks_cloudwatch_kms_key.key_arn
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
    iam_role_additional_policies = {
      AmazonEC2ContainerRegistryReadOnly = "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
      CloudWatchAgentServerPolicy        = "arn:${local.partition}:iam::aws:policy/CloudWatchAgentServerPolicy",
      EKSPullThroughCachePolicy          = var.ecr_pull_through_cache_policy_arn,
    }
  }

  eks_managed_node_groups = local.eks_worker_group_map

  # aws-auth configmap
  manage_aws_auth_configmap = true
  aws_auth_roles = concat(var.input_role, [
    {
      rolearn  = var.node_drainer_lambda_role_arn
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
        create = "25m"
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
    create          = true
    use_name_prefix = false
    retention       = 30
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

  depends_on = [
    # Wait for EKS to be deployed first
    module.eks,
  ]
}


resource "time_sleep" "eks_blueprints_addons_dependency" {
  # Giving TF some time to create the  EKS Blueprints Addons, ie the AWS Load Balancer Controller
  # and CoreDns and also allowing ie AWS LB Controller to delete resources before it is destroyed
  create_duration  = "30s"
  destroy_duration = "60s"

  triggers = {
    aws_load_balancer_controller = module.eks_blueprints_addons.aws_load_balancer_controller.name
    coredns_arn                  = module.eks_blueprints_addons.eks_addons["coredns"].arn
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
