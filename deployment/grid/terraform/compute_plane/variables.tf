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

variable "k8s_ca_version" {
  description = "Cluster autoscaler version"
}

variable "k8s_keda_version" {
  description = "Keda version"
}

variable "ddb_state_table" {
  description = "HTC DynamoDB table name"
}

variable "sqs_queue" {
  description = "HTC SQS queue name"
}

variable "tasks_queue_name" {
  description = "HTC queue name"
}

variable "task_queue_service" {
  description = "Configuration string for the type of queuing service to use"
}

variable "task_queue_config" {
  description = "Dictionary configuration of the tasks queue"
}


# variable "dimension_value_metrics" {
#   default  = "[{DimensionName=cluster_name,DimensionValue=htc-aws}, {DimensionName=env,DimensionValue=dev}]"
#   description = "Dimensions name/value for the CloudWatch metrics"
# }


variable "lambda_name_scaling_metrics" {
  description = "Lambda function name for metrics"
}


variable "namespace_metrics" {
  description = "NameSpace for metrics"
}

variable "dimension_name_metrics" {
  description = "Dimensions name/value for the CloudWatch metrics"
}


variable "period_metrics" {
  description = "Period for metrics in minutes"
}

variable "metric_name" {
  description = "Metrics name"
}

variable "error_log_group" {
  description = "Log group for errors"
}

variable "error_logging_stream" {
  description = "Log stream for errors"
}

variable "metrics_event_rule_time" {
  description = "Fires event rule to put metrics"
}




variable "suffix" {
  default = ""
  description = "suffix for generating unique name for AWS resource"
}

variable "eks_worker_groups" {
  type        = any
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

variable "state_table_service" {
  description = "State Table service type"
}

variable "state_table_config" {
  description = "Status Table configuration"
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