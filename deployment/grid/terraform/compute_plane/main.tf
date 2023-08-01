# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

locals {
  # check if var.suffix is empty then create a random suffix else use var.suffix
  suffix = var.suffix != "" ? var.suffix : random_string.random.result

  eks_worker_group = concat([
    for index in range(0, length(var.eks_worker_groups)) :
    merge(var.eks_worker_groups[index], {
      labels = {
        "htc/node-type" = "worker"
      }

      tags = {
        "aws-node-termination-handler/managed"          = "true"
        "k8s.io/cluster-autoscaler/enabled"             = "true"
        "k8s.io/cluster-autoscaler/${var.cluster_name}" = "true"
      }
    })
    ],
    [
      {
        node_group_name = "core-ondemand",
        # instance_types  = ["m6i.xlarge", "m6id.xlarge", "m6a.xlarge", "m6in.xlarge", "m5.xlarge", "m5d.xlarge", "m5a.xlarge", "m5ad.xlarge", "m5n.xlarge"],
        capacity_type = "ON_DEMAND",
        iam_role_additional_policies = {
          agent_permissions = aws_iam_policy.agent_permissions.arn
        }
        min_size     = 2,
        max_size     = 6,
        desired_size = 2,

        labels = {
          "htc/node-type" = "core"
        }

        taints = [
          {
            key    = "htc/node-type"
            value  = "core"
            effect = "NO_SCHEDULE"
          }
        ]
      }
    ]
  )

  eks_worker_group_name = [
    for index in range(0, length(local.eks_worker_group)) :
    local.eks_worker_group[index].node_group_name
  ]

  eks_worker_group_map = zipmap(local.eks_worker_group_name, local.eks_worker_group)
}


resource "random_string" "random" {
  length  = 10
  special = false
  upper   = false
}


################################################################################
# Tags for the ASG to support cluster-autoscaler scale up from 0
################################################################################
locals {
  # We need to lookup K8s taint effect from the AWS API value
  taint_effects = {
    NO_SCHEDULE        = "NoSchedule"
    NO_EXECUTE         = "NoExecute"
    PREFER_NO_SCHEDULE = "PreferNoSchedule"
  }

  cluster_autoscaler_label_tags = merge([
    for name, group in module.eks.eks_managed_node_groups : {
      for label_name, label_value in coalesce(group.node_group_labels, {}) : "${name}|label|${label_name}" => {
        autoscaling_group = group.node_group_autoscaling_group_names[0],
        key               = "k8s.io/cluster-autoscaler/node-template/label/${label_name}",
        value             = label_value,
      }
    }
  ]...)

  cluster_autoscaler_taint_tags = merge([
    for name, group in module.eks.eks_managed_node_groups : {
      for taint in coalesce(group.node_group_taints, []) : "${name}|taint|${taint.key}" => {
        autoscaling_group = group.node_group_autoscaling_group_names[0],
        key               = "k8s.io/cluster-autoscaler/node-template/taint/${taint.key}"
        value             = "${taint.value}:${local.taint_effects[taint.effect]}"
      }
    }
  ]...)

  cluster_autoscaler_asg_tags = merge(local.cluster_autoscaler_label_tags, local.cluster_autoscaler_taint_tags)
}

resource "aws_autoscaling_group_tag" "cluster_autoscaler_label_tags" {
  for_each = local.cluster_autoscaler_asg_tags

  autoscaling_group_name = each.value.autoscaling_group

  tag {
    key   = each.value.key
    value = each.value.value

    propagate_at_launch = false
  }
}
