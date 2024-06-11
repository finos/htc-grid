# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


locals {
  # check if var.suffix is empty then create a random suffix else use var.suffix
  suffix     = var.suffix != "" ? var.suffix : random_string.random.result
  account_id = data.aws_caller_identity.current.account_id
  dns_suffix = data.aws_partition.current.dns_suffix
  partition  = data.aws_partition.current.partition

  eks_worker_group = concat([
    for index in range(0, length(var.eks_worker_groups)) :
    merge(var.eks_worker_groups[index], {
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = var.eks_node_volume_size
            volume_type           = "gp3"
            encrypted             = true
            kms_key_id            = module.eks_ebs_kms_key.key_arn
            delete_on_termination = true
          }
        }
      }

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
        capacity_type   = "ON_DEMAND",

        min_size     = 2,
        max_size     = 6,
        desired_size = 2,

        block_device_mappings = {
          xvda = {
            device_name = "/dev/xvda"
            ebs = {
              volume_size           = var.eks_node_volume_size
              volume_type           = "gp3"
              encrypted             = true
              kms_key_id            = module.eks_ebs_kms_key.key_arn
              delete_on_termination = true
            }
          }
        }

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

  eks_worker_group_names = [
    for index in range(0, length(local.eks_worker_group)) :
    local.eks_worker_group[index].node_group_name
  ]

  eks_worker_group_map = zipmap(local.eks_worker_group_names, local.eks_worker_group)

  default_kms_key_admin_arns = [
    data.aws_caller_identity.current.arn,
    "arn:${local.partition}:iam::${local.account_id}:root"
  ]
  additional_kms_key_admin_role_arns = [for k, v in data.aws_iam_role.additional_kms_key_admin_roles : v.arn]
  kms_key_admin_arns                 = concat(local.default_kms_key_admin_arns, local.additional_kms_key_admin_role_arns)

  asg_service_linked_role_exists = length(data.aws_iam_roles.check_asg_service_linked_role.arns) > 0 ? true : false
  asg_service_linked_role_arns   = local.asg_service_linked_role_exists ? data.aws_iam_roles.check_asg_service_linked_role.arns : [aws_iam_service_linked_role.asg_service_linked_role[0].arn]

  eks_managed_node_group_asg_names = {
    for eks_worker_group_name in local.eks_worker_group_names :
    eks_worker_group_name => {
      "asg_name" = join("", [
        for eks_mng_asg_name in module.eks.eks_managed_node_groups_autoscaling_group_names : eks_mng_asg_name
        if startswith(eks_mng_asg_name, "eks-${eks_worker_group_name}-")
      ])
    }
  }

  eks_managed_node_groups = {
    for eks_worker_group_name, eks_managed_node_group in local.eks_managed_node_group_asg_names :
    eks_worker_group_name => {
      "name" = eks_managed_node_group.asg_name
      "arn"  = data.aws_autoscaling_group.eks_managed_node_group_autoscaling_groups[eks_worker_group_name].arn
    }
  }
}


resource "aws_iam_service_linked_role" "asg_service_linked_role" {
  count = local.asg_service_linked_role_exists ? 0 : 1

  aws_service_name = "autoscaling.${local.dns_suffix}"
}


module "eks_ebs_kms_key" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 2.0"

  description             = "CMK KMS Key used to encrypt EKS Managed Node Group volumes"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true

  key_administrators = local.kms_key_admin_arns

  key_service_roles_for_autoscaling = flatten([
    # Required for the ASG to manage encrypted volumes for nodes
    local.asg_service_linked_role_arns,
    # Required for the Cluster / persistentvolume-controller to create encrypted PVCs
    module.eks.cluster_iam_role_arn,
  ])

  aliases = ["eks/${var.cluster_name}/ebs"]
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
