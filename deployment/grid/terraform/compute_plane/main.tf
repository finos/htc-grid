# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

locals {
  # check if var.suffix is empty then create a random suffix else use var.suffix
  suffix = var.suffix != "" ? var.suffix : random_string.random_resources.result

  eks_worker_group = concat([
    for index in range(0,length(var.eks_worker_groups)):
      merge(var.eks_worker_groups[index], {
        additional_iam_policies = [
          "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
          aws_iam_policy.eks_pull_through_cache_permission.arn
        ]
        launch_template_os   = "amazonlinux2eks"
        additional_tags = {
          "k8s.io/cluster-autoscaler/enabled"    = "true"
          "k8s.io/cluster-autoscaler/${var.cluster_name}"= "true"
        }})
        ],[
          {
            node_group_name = "operational-worker-ondemand",
            instance_types = ["m5.xlarge","m4.xlarge","m5d.xlarge"],
            capacity_type          = "ON_DEMAND",
            additional_iam_policies = [
              "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
              aws_iam_policy.eks_pull_through_cache_permission.arn,
              aws_iam_policy.agent_permissions.arn
            ]
            min_size            = 2,
            max_size           = 5,
            desired_size    = 2,
            launch_template_os   = "amazonlinux2eks"
            kubelet_extra_args      = "--node-labels=grid/type=Operator --register-with-taints=grid/type=Operator:NoSchedule"
    }

  ])
  eks_worker_group_name = [
    for index in range(0,length(local.eks_worker_group)):
          local.eks_worker_group[index].node_group_name
  ]

  eks_worker_group_map = zipmap(local.eks_worker_group_name,local.eks_worker_group )
}

resource "random_string" "random_resources" {
  length = 10
  special = false
  upper = false
  # number = false
}

data aws_caller_identity current {}