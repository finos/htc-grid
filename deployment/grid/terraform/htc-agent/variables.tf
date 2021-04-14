# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

variable "agent_chart_url" {
  type = string
  description = "location where the agent chart is located"
  default = "../src/eks/"
}

variable "agent_namespace" {
  type = string
  description = "kubernetes namespace where the agent is created"
  default = "default"
}

variable "agent_image_repository" {
  type = string
  description = "repository of the agent image"
}

variable "agent_image_tag" {
  type = string
  description = "tag associated to the agent image"
}

variable "test_agent_image_repository" {
  type = string
  description = "repository of the test agent image"
}

variable "test_agent_image_tag" {
  type = string
  description = "tag associated to the test agent image"
}

variable "lambda_image_repository" {
  type = string
  description = "repository to the lambda image"
}

variable "lambda_image_tag" {
  type = string
  description = "tag associated to the lambda image"
}

variable "get_layer_image_repository" {
  type = string
  description = "repository of the get-layer image"
}

variable "get_layer_image_tag" {
  type = string
  description = "tag associated to the get-layer image"
}

variable "agent_name" {
  type = string
  description = "name of the kubernetes deployment managing the image"
  default = "htc-agent"
}

variable "agent_min_cpu" {
  type = number
  description = "Minimum CPU asisgned to the agent (in milli)"
  default = 10
}

variable "agent_max_cpu" {
  type = number
  description = "Maximum CPU asisgned to the agent (in milli)"
  default = 50
}

variable "lambda_min_cpu" {
  type = number
  description = "Minimum CPU asisgned to the lambda (in milli)"
}

variable "lambda_max_cpu" {
  type = number
  description = "Maximum CPU asisgned to the lambda (in milli)"
}

variable "agent_min_memory" {
  type = number
  description = "Minimum memory asisgned to the agent (in MiB)"
  default = 100
}

variable "agent_max_memory" {
  type = number
  description = "Maximum memory asisgned to the agent (in MiB)"
  default = 100
}

variable "lambda_min_memory" {
  type = number
  description = "Minimum memory asisgned to the agent (in MiB)"
  default = 100
}

variable "lambda_max_memory" {
  type = string
  description = "Maximum memory asisgned to the agent (in MiB)"
  default = 100
}

variable "agent_pull_policy" {
  type = string
  description = "pull policy for agent image"
  default = "IfNotPresent"
}

variable "lambda_pull_policy" {
  type = string
  description = "pull policy for lambda image"
  default = "IfNotPresent"
}

variable "get_layer_pull_policy" {
  type = string
  description = "pull policy for the get_layer image"
  default = "IfNotPresent"
}

variable "test_pull_policy" {
  type = string
  description = "pull policy for agent image"
  default = "IfNotPresent"
}

variable "termination_grace_period" {
  type = number
  description = "termination grace period in second"
  default = 1500
}

variable "lambda_configuration_storage_type" {
  type = string
  description = "storage type for Lambda Layer either \"Layer\" or \"S3\""
  default = "S3"
}

variable "lambda_configuration_location" {
  type = string
  description = "The location of the S3 bucket"
}

variable "lambda_configuration_region" {
  type = string
  description = "The region of the Lambda Layer"
  default = "eu-west-1"
}

variable "lambda_configuration_layer_name" {
  type = string
  description = "The name of the lambda layer storing the source code"
  default = "mock_layer"
}

variable "lambda_configuration_layer_version" {
  type = number
  description = "The version of the lambda layer storing the source code"
  default = 1
}

variable "lambda_configuration_function_name" {
  type = string
  description = "The name of the lambda function to be executed"
  default = "mock_computation"
}


variable "lambda_handler_file_name" {
  type = string
  description = "The file name  of the lambda handler"
}

variable "lambda_handler_function_name" {
  type = string
  description = "The function name of the lambda handler"
}