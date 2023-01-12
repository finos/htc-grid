# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/



#resource "helm_release" "eks-charts" {
#  name       = "aws-node-termination-handler"
#  chart      = "../charts/aws-node-termination-handler/${var.aws_node_termination_handler_version}"
#  namespace  = "kube-system"
#
#
#  set {
#    name  = "image.repository" #Values.image.repository
#    value = "${var.aws_htc_ecr}/amazon/aws-node-termination-handler"
#  }
#
#  set {
#    name  = "image.tag" #Values.image.repository
#    value = var.aws_node_termination_handler_version
#  }
#}




module "eks" {
  source  = "github.com/aws-ia/terraform-aws-eks-blueprints"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version
  private_subnet_ids = var.vpc_private_subnet_ids



  cluster_endpoint_private_access = var.enable_private_subnet
  cluster_enabled_log_types = ["api","audit","authenticator","controllerManager","scheduler"]

  self_managed_node_groups = local.eks_worker_group_map
  create_iam_role = true
  vpc_id = var.vpc_id

}

data "aws_eks_cluster" "cluster" {
  name = module.eks.eks_cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.eks_cluster_id
}


module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons"

  eks_cluster_id       = module.eks.eks_cluster_id
  eks_cluster_endpoint = data.aws_eks_cluster.cluster.endpoint
  eks_oidc_provider    = replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")
  eks_cluster_version  = data.aws_eks_cluster.cluster.version

  auto_scaling_group_names = module.eks.self_managed_node_group_autoscaling_groups
  # EKS Managed Addons
  enable_amazon_eks_aws_ebs_csi_driver = true

  enable_aws_for_fluentbit                 = true
  aws_for_fluentbit_create_cw_log_group    = true
  aws_for_fluentbit_cw_log_group_retention = 30
  aws_for_fluentbit_helm_config = {
    create_namespace = true
    values = [templatefile("${path.module}/../../charts/values/aws-for-fluentbit.yaml", {
      region = var.region
      account_id       = data.aws_caller_identity.current.account_id
    })]
  }

  enable_prometheus = true
  prometheus_helm_config = {
    create_namespace = true
    values = [templatefile("${path.module}/../../charts/values/prometheus.yaml", {
      region = var.region
      account_id       = data.aws_caller_identity.current.account_id
      kube_state_metrics_tag = var.prometheus_configuration.kube_state_metrics_tag
      configmap_reload_tag = var.prometheus_configuration.configmap_reload_tag
    })]
  }

  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller_helm_config = {
    service_account = "aws-lb-sa"
    values = [templatefile("${path.module}/../../charts/values/aws-alb-controller.yaml", {
      region = var.region
      eks_cluster_id =  module.eks.eks_cluster_id
    })]
  }

  enable_grafana = true
  grafana_helm_config = {
    values = [templatefile("${path.module}/../../charts/values/grafana.yaml", {
      aws_htc_ecr = var.aws_htc_ecr
      eks_cluster_id =  module.eks.eks_cluster_id
      grafana_configuration_initChownData_tag = var.grafana_configuration.initChownData_tag
      grafana_configuration_grafana_tag = var.grafana_configuration.grafana_tag
      grafana_configuration_downloadDashboardsImage_tag = var.grafana_configuration.downloadDashboardsImage_tag
      grafana_configuration_sidecar_tag = var.grafana_configuration.sidecar_tag
    })]
  }

  enable_aws_node_termination_handler = true
  aws_node_termination_handler_helm_config = {
    values = [templatefile("${path.module}/../../charts/values/aws-node-termination-handler.yaml", {
      aws_htc_ecr = var.aws_htc_ecr
      eks_cluster_id =  module.eks.eks_cluster_id
      region = var.region
      k8s_ca_version = var.k8s_ca_version
    })]
  }

  enable_cluster_autoscaler = true
  cluster_autoscaler_helm_config = {
    values = [templatefile("${path.module}/../../charts/values/cluster-autoscaler.yaml", {
      aws_htc_ecr = var.aws_htc_ecr
      eks_cluster_id =  module.eks.eks_cluster_id
      region = var.region
      k8s_ca_version = var.k8s_ca_version
    })]
  }

#  enable_aws_cloudwatch_metrics = true
#  aws_cloudwatch_metrics_helm_config = {
#    values = [
#      templatefile("${path.module}/../../charts/values/aws-cloudwatch-metrics.yaml", {
#        aws_htc_ecr    = var.aws_htc_ecr
#        eks_cluster_id = module.eks.eks_cluster_id
#      })
#    ]
#  }

  depends_on = [
    null_resource.patch_coredns
  ]
}

module "htc_agent_irsa" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/irsa"
  create_kubernetes_namespace = false
  create_kubernetes_service_account = true
  eks_cluster_id = module.eks.eks_cluster_id
  eks_oidc_provider_arn = module.eks.eks_oidc_provider_arn
  irsa_iam_policies = [aws_iam_policy.agent_permissions.arn]
  irsa_iam_role_name = "IrsaForHTCAgentRole"
  kubernetes_namespace = "default"
  kubernetes_service_account = "htc-agent-sa"
}


data "local_file" "patch_core_dns" {
    filename = "${path.module}/patch-toleration-selector.yaml"
}

resource "null_resource" "update_kubeconfig" {
  triggers = {
    #cluster_arn = "arn:aws:eks:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"
    cluster_arn = module.eks.eks_cluster_arn
  }
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name}"
  }
  provisioner "local-exec" {
    when = destroy
    command = "kubectl config delete-cluster ${self.triggers.cluster_arn}"
  }
  provisioner "local-exec" {
    when = destroy
    command = "kubectl config delete-context ${self.triggers.cluster_arn}"
  }

}

resource "null_resource" "patch_coredns" {
    provisioner "local-exec" {
    command = "kubectl -n kube-system patch deployment coredns --patch \"${data.local_file.patch_core_dns.content}\""
  }
  depends_on = [module.eks]
}

