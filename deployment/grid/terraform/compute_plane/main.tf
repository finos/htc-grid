# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

locals {
  # check if var.suffix is empty then create a random suffix else use var.suffix
  suffix = var.suffix != "" ? var.suffix : random_string.random_resources.result

  eks_worker_group = concat([
    for index in range(0,length(var.eks_worker_groups)):
      merge(var.eks_worker_groups[index], {
        "spot_allocation_strategy" = "capacity-optimized"
        "tags" = [
          {
            key                = "k8s.io/cluster-autoscaler/enabled"
            propagate_at_launch = "false"
            value              = "true"
          },
          {
            key                 = "k8s.io/cluster-autoscaler/${var.cluster_name}"
            propagate_at_launch = "false"
            value               = "true"
          }
        ]
      })
  ],[
    {
      name = "operational-worker-ondemand",
      override_instance_types = ["m5.2xlarge","m4.2xlarge","m5d.2xlarge"],
      spot_instance_pools    = 0,
      asg_min_size            = 2,
      asg_max_size           = 5,
      asg_desired_capacity    = 2,
      on_demand_base_capacity = 2,
      on_demand_percentage_above_base_capacity = 100,
      spot_allocation_strategy = "capacity-optimized",
      kubelet_extra_args      = "--node-labels=grid/type=Operator --register-with-taints=grid/type=Operator:NoSchedule"
    }
  ])
  args_ca = [
    for index in range(0,length(var.eks_worker_groups)):
    "--nodes=${var.eks_worker_groups[index].asg_min_size}:${var.eks_worker_groups[index].asg_max_size}:${module.eks.workers_asg_names[index]}"
  ]
}

resource "random_string" "random_resources" {
  length = 10
  special = false
  upper = false
  # number = false
}