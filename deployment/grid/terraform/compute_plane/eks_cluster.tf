# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/



resource "helm_release" "eks-charts" {
  name       = "aws-node-termination-handler"
  chart      = "./compute_plane/charts/aws-node-termination-handler/${var.aws_node_termination_handler_version}"
  namespace  = "kube-system"
  depends_on = [
    module.eks
  ]

  set {
    name  = "image.repository" #Values.image.repository
    value = "${var.aws_htc_ecr}/amazon/aws-node-termination-handler"
  }

  set {
    name  = "image.tag" #Values.image.repository
    value = var.aws_node_termination_handler_version
  }
}




module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "17.1.0"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version
  subnets         = var.vpc_private_subnet_ids


  kubeconfig_aws_authenticator_command = "aws"
  kubeconfig_aws_authenticator_command_args = [
    "--region",
    var.region,
    "eks",
    "get-token",
    "--cluster-name",
    var.cluster_name,
  ]

  # wait_for_cluster_interpreter = ["C:/Program Files/Git/bin/sh.exe", "-c"]
  cluster_endpoint_private_access = var.enable_private_subnet
  cluster_enabled_log_types = ["api","audit","authenticator","controllerManager","scheduler"]
  tags = {
    Environment = "training"
    GithubRepo  = "terraform-aws-eks"
    GithubOrg   = "terraform-aws-modules"
    Application = "htc-grid-solution"
  }

  worker_groups_launch_template = local.eks_worker_group

  vpc_id = var.vpc_id
  map_roles = concat([
    {
      rolearn  = module.eks.worker_iam_role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups   = ["system:bootstrappers","system:nodes"]
    },
    {
      rolearn  = aws_iam_role.role_lambda_drainer.arn
      username = "lambda"
      groups   = ["system:masters"]
    },
  ],
  var.input_role)
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

data "local_file" "patch_core_dns" {
    filename = "${path.module}/patch-toleration-selector.yaml"
}

resource "null_resource" "update_kubeconfig" {
  triggers = {
    #cluster_arn = "arn:aws:eks:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"
    cluster_arn = module.eks.cluster_arn
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
  depends_on = [
    module.eks
  ]
}

resource "null_resource" "patch_coredns" {
    provisioner "local-exec" {
    command = "kubectl -n kube-system patch deployment coredns --patch \"${data.local_file.patch_core_dns.content}\""
    environment = {
      KUBECONFIG  = module.eks.kubeconfig_filename
    }
  }
  depends_on = [
    module.eks
  ]
}

