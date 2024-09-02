# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

variable "agent_chart_url" {
  description = "location where the agent chart is located"
  type        = string
  default     = "../src/eks/"
}

variable "agent_namespace" {
  description = "kubernetes namespace where the agent is created"
  type        = string
  default     = "default"
}

variable "agent_image_repository" {
  description = "repository of the agent image"
  type        = string
}

variable "agent_image_tag" {
  description = "tag associated to the agent image"
  type        = string
}

variable "htc_agent_permissions_policy_arn" {
  description = "IAM Policy ARN for HTC Agent IRSA Permissions"
  type        = string
}

variable "suffix" {
  description = "suffix for generating unique name for AWS resource"
  type        = string
  default     = ""
}

variable "eks_oidc_provider_arn" {
  description = "EKS Cluster OIDC Provider ARN for IRSA Permissions"
  type        = string
}

variable "test_agent_image_repository" {
  description = "repository of the test agent image"
  type        = string
}

variable "test_agent_image_tag" {
  description = "tag associated to the test agent image"
  type        = string
}

variable "lambda_image_repository" {
  description = "repository to the lambda image"
  type        = string
}

variable "lambda_image_tag" {
  description = "tag associated to the lambda image"
  type        = string
}

variable "get_layer_image_repository" {
  description = "repository of the get-layer image"
  type        = string
}

variable "get_layer_image_tag" {
  description = "tag associated to the get-layer image"
  type        = string
}

variable "agent_name" {
  description = "name of the kubernetes deployment managing the image"
  type        = string
  default     = "htc-agent"
}

variable "agent_min_cpu" {
  description = "Minimum CPU asisgned to the agent (in milli)"
  type        = number
  default     = 10
}

variable "agent_max_cpu" {
  description = "Maximum CPU asisgned to the agent (in milli)"
  type        = number
  default     = 50
}

variable "lambda_min_cpu" {
  description = "Minimum CPU asisgned to the lambda (in milli)"
  type        = number
}

variable "lambda_max_cpu" {
  description = "Maximum CPU asisgned to the lambda (in milli)"
  type        = number
}

variable "agent_min_memory" {
  description = "Minimum memory asisgned to the agent (in MiB)"
  type        = number
  default     = 100
}

variable "agent_max_memory" {
  description = "Maximum memory asisgned to the agent (in MiB)"
  type        = number
  default     = 100
}

variable "lambda_min_memory" {
  description = "Minimum memory asisgned to the agent (in MiB)"
  type        = number
  default     = 100
}

variable "lambda_max_memory" {
  description = "Maximum memory asisgned to the agent (in MiB)"
  type        = number
  default     = 100
}

variable "agent_pull_policy" {
  description = "pull policy for agent image"
  type        = string
  default     = "IfNotPresent"
}

variable "lambda_pull_policy" {
  description = "pull policy for lambda image"
  type        = string
  default     = "IfNotPresent"
}

variable "get_layer_pull_policy" {
  description = "pull policy for the get_layer image"
  type        = string
  default     = "IfNotPresent"
}

variable "test_pull_policy" {
  description = "pull policy for agent image"
  type        = string
  default     = "IfNotPresent"
}

variable "termination_grace_period" {
  description = "termination grace period in second"
  type        = number
  default     = 1500
}

variable "lambda_configuration_storage_type" {
  description = "Storage type for Lambda Layer either [Layer] or [S3]"
  type        = string
  default     = "S3"
}

variable "lambda_configuration_s3_source" {
  description = "The Lambda Layer S3 bucket source"
  type        = string
}

# variable "lambda_configuration_s3_source_kms_key_arn" {
#   description = "The CMK KMS Key ARN for the Lambda Layer S3 bucket source"
#   type        = string
# }

variable "region" {
  description = "The region of the Lambda Layer"
  type        = string
  default     = "eu-west-1"
}

# variable "lambda_configuration_layer_name" {
#   description = "The name of the lambda layer storing the source code"
#   type        = string
#   default     = "mock_layer"
# }

# variable "lambda_configuration_layer_version" {
#   description = "The version of the lambda layer storing the source code"
#   type        = number
#   default     = 1
# }

variable "lambda_configuration_function_name" {
  description = "The name of the lambda function to be executed"
  type        = string
  default     = "mock_computation"
}

variable "lambda_handler_file_name" {
  description = "The file name  of the lambda handler"
  type        = string
}

variable "lambda_handler_function_name" {
  description = "The function name of the lambda handler"
  type        = string
}

variable "namespace_metrics" {
  description = "NameSpace for metrics"
  type        = string
}

variable "dimension_name_metrics" {
  description = "Dimensions name for the CloudWatch metrics"
  type        = string
}

variable "dimension_value_metrics" {
  description = "Dimensions name for the CloudWatch metrics"
  type        = string
}

# variable "average_period" {
#   description = "Average period in second used by the HPA to compute the current load on the system"
#   type        = number
#   default     = 30
# }

variable "metric_name" {
  description = "Metrics name"
  type        = string
}

variable "max_htc_agents" {
  description = "maximum number of agents that can run on EKS"
  type        = number
}

variable "min_htc_agents" {
  description = "minimum number of agents that can run on EKS"
  type        = number
}

variable "htc_agent_target_value" {
  description = "target value for the load on the system"
  type        = number
}
