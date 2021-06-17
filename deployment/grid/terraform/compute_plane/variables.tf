# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/
 
variable "region" {
  description = "AWS region"
}

# variable "cluster_name" {
#   default = "htc_aws"
#   description = "Name of EKS cluster in AWS"
# }

variable "input_role" {
  description = "Additional IAM roles to add to the aws-auth configmap."
  type = list(object({
    rolearn  = string
    username = string
    groups   = list(string)
  }))
}

variable "kubernetes_version" {
  description = "Name of EKS cluster in AWS"
}

variable "aws_htc_ecr" {
  description = "URL of Amazon ECR image repostiories"
}

variable "lambda_runtime" {
  description = "Python version"
  default = "python3.7"
}

variable "cwa_version" {
  description = "Cloud Watch Adapter for kubernetes version"
}

variable "aws_node_termination_handler_version" {
  description = "version of the deployment managing node termination"
}

variable "cw_agent_version" {
  description = "CloudWatch Agent version"
}

variable "fluentbit_version" {
  description = "Fluentbit version"
}


variable "cluster_name" {
  description = "Name of EKS cluster in AWS"
}

# variable "aws_asg_min_instances" {
#   default  = "1"
#   description = "Minimum number of instances for autoscaling group"
# }

# variable "aws_asg_max_instances" {
#   default  = "5"
#   description = "Max number of instances for autoscaling group"
# }

# variable "instance_type" {
#   default = "t2.small"
#   description = "instance type for worker nodes"
# }

variable "k8s_ca_version" {
  description = "Cluster autoscaler version"
}

variable "ddb_status_table" {
  description = "HTC DynamoDB table name"
}

variable "sqs_queue" {
  description = "HTC SQS queue name"
}

variable "namespace_metrics" {
  description = "NameSpace for metrics"
}


variable "dimension_name_metrics" {
  description = "Dimensions name/value for the CloudWatch metrics"
}


variable "htc_path_logs" {
  description = "Path to fluentD to search de logs application"
}

# variable "dimension_value_metrics" {
#   default  = "[{DimensionName=cluster_name,DimensionValue=htc-aws}, {DimensionName=env,DimensionValue=dev}]"
#   description = "Dimensions name/value for the CloudWatch metrics"
# }


variable "lambda_name_scaling_metrics" {
  description = "Lambda function name for metrics"
}

variable "average_period" {
  default = 30
  description = "Average period in second used by the HPA to compute the current load on the system"
}


variable "period_metrics" {
  description = "Period for metrics in minutes"
}

variable "metric_name" {
  description = "Metrics name"
}

variable "metrics_event_rule_time" {
  description = "Fires event rule to put metrics"
}

variable "htc_agent_name" {
  description = "name of the htc agent to scale out/in"
}

variable "htc_agent_namespace" {
  description = "kubernetes namespace for the deployment of the agent"
}

variable "suffix" {
  default = ""
  description = "suffix for generating unique name for AWS resource"
}

variable "eks_worker_groups" {
  type        = any
}

variable "max_htc_agents" {
  description = "maximum number of agents that can run on EKS"
}

variable "min_htc_agents" {
  description = "minimum number of agents that can run on EKS"
}

variable "htc_agent_target_value" {
  description = "target value for the load on the system"
}

variable "vpc_private_subnet_ids" {
  description = "Private subnet IDs"
}

variable "graceful_termination_delay" {
  description = "graceful termination delay for scaled in action"
}

variable "vpc_public_subnet_ids" {
  description = "Public subnet IDs"
}

variable "vpc_default_security_group_id" {
  description = "Default SG ID"
}

variable "vpc_id" {
  description = "Default VPC ID"
}

variable "vpc_cidr" {
  description = "Default VPC CIDR"
}

variable "aws_xray_daemon_version" {
  description = "version for the XRay daemon"
  type = string
}

variable "enable_private_subnet" {
  description = "enable private subnet"
  type = bool
}

variable "grafana_configuration" {
  description = "this variable store the configuration for the grafana helm chart"
  type = object({
    downloadDashboardsImage_tag = string
    grafana_tag = string
    initChownData_tag = string
    sidecar_tag = string
    admin_password = string

    # busybox


  })
}

variable "prometheus_configuration" {
  description = "this variable store the configuration for the prometheus helm chart"
  type = object({
    node_exporter_tag = string
    server_tag = string
    alertmanager_tag = string
    kube_state_metrics_tag = string
    pushgateway_tag = string
    configmap_reload_tag = string
  })
}