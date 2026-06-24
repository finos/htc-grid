# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


locals {
  account_id                  = data.aws_caller_identity.current.account_id
  dns_suffix                  = data.aws_partition.current.dns_suffix
  aws_htc_ecr                 = var.aws_htc_ecr != "" ? var.aws_htc_ecr : "${local.account_id}.dkr.ecr.${var.region}.${local.dns_suffix}"
  project_name                = var.project_name != "" ? var.project_name : random_string.random_resources.result
  grafana_admin_password      = var.grafana_admin_password != "" ? var.grafana_admin_password : random_password.password.result
  cluster_name                = "${var.cluster_name}-${local.project_name}"
  ddb_state_table             = "${var.ddb_state_table}-${local.project_name}"
  sqs_queue                   = "${var.sqs_queue}-${local.project_name}"
  tasks_queue_name            = "${var.sqs_queue}-${local.project_name}__0"
  sqs_dlq                     = "${var.sqs_dlq}-${local.project_name}"
  lambda_name_get_results     = "${var.lambda_name_get_results}-${local.project_name}"
  lambda_name_submit_tasks    = "${var.lambda_name_submit_tasks}-${local.project_name}"
  lambda_name_cancel_tasks    = "${var.lambda_name_cancel_tasks}-${local.project_name}"
  lambda_name_ttl_checker     = "${var.lambda_name_ttl_checker}-${local.project_name}"
  lambda_name_scaling_metrics = "${var.lambda_name_scaling_metrics}-${local.project_name}"
  lambda_name_node_drainer    = "${var.lambda_name_node_drainer}-${local.project_name}"
  metrics_name                = "${var.metrics_name}-${local.project_name}"
  s3_bucket                   = "${var.s3_bucket}-${local.project_name}"
  error_log_group             = "${var.error_log_group}-${local.project_name}"
  error_logging_stream        = "${var.error_logging_stream}-${local.project_name}"
  default_vpc_cidr_blocks     = data.aws_vpc.default.cidr_block_associations[*].cidr_block
  allowed_access_cidr_blocks  = concat(var.allowed_access_cidr_blocks, local.default_vpc_cidr_blocks)

  default_agent_configuration = {
    agent_chart_url = "../charts"
    agent = {
      image      = "${local.aws_htc_ecr}/awshpc-lambda"
      tag        = local.project_name
      pullPolicy = "IfNotPresent"
      minCPU     = "10"
      maxCPU     = "50"
      maxMemory  = "100"
      minMemory  = "50"
    }

    lambda = {
      image                        = "${local.aws_htc_ecr}/lambda"
      runtime                      = "provided"
      pullPolicy                   = "IfNotPresent"
      minCPU                       = "800"
      maxCPU                       = "900"
      maxMemory                    = "3900"
      minMemory                    = "4096"
      storage                      = "S3"
      s3_source                    = "s3://mock_location"
      s3_source_kms_key_arn        = "arn:aws:kms:${var.region}:${local.account_id}:key/mock_key_arn"
      function_name                = "function"
      layer_name                   = "mock_computation_layer"
      lambda_handler_file_name     = ""
      lambda_handler_function_name = ""
      layer_version                = 1
      region                       = var.region
    }

    get_layer = {
      image             = "${local.aws_htc_ecr}/lambda-init"
      tag               = local.project_name
      pullPolicy        = "IfNotPresent"
      lambda_layer_type = "S3"
    }

    test = {
      image      = "${local.aws_htc_ecr}/submitter"
      tag        = local.project_name
      pullPolicy = "IfNotPresent"
    }
  }
}


# Retrieve the account ID
data "aws_caller_identity" "current" {}


# Retrieve AWS Partition
data "aws_partition" "current" {}


# Default VPC
data "aws_vpc" "default" {
  default = true
}

resource "random_string" "random_resources" {
  length  = 5
  special = false
  upper   = false
  # number = false
}


resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "_%@!"
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
}


module "vpc" {
  source = "./vpc"

  region                     = var.region
  cluster_name               = local.cluster_name
  vpc_range                  = 16
  private_subnets            = var.vpc_cidr_block_private
  public_subnets             = var.vpc_cidr_block_public
  enable_private_subnet      = var.enable_private_subnet
  allowed_access_cidr_blocks = local.allowed_access_cidr_blocks
  kms_key_admin_roles        = var.kms_key_admin_roles
  kms_deletion_window        = var.kms_deletion_window
}


module "compute_plane" {
  source = "./compute_plane"
  count  = var.worker_backend == "eks" ? 1 : 0

  vpc_id                            = module.vpc.vpc_id
  vpc_private_subnet_ids            = module.vpc.private_subnet_ids
  vpc_public_subnet_ids             = module.vpc.public_subnet_ids
  cluster_name                      = local.cluster_name
  kubernetes_version                = var.kubernetes_version
  k8s_ca_version                    = var.k8s_ca_version
  k8s_keda_version                  = var.k8s_keda_version
  aws_htc_ecr                       = local.aws_htc_ecr
  suffix                            = local.project_name
  region                            = var.region
  eks_worker_groups                 = var.eks_worker_groups
  eks_node_volume_size              = var.eks_node_volume_size
  input_role                        = var.input_role
  enable_private_subnet             = var.enable_private_subnet
  grafana_admin_password            = local.grafana_admin_password
  ecr_pull_through_cache_policy_arn = module.control_plane.ecr_pull_through_cache_policy_arn
  node_drainer_lambda_role_arn      = module.control_plane.node_drainer_lambda_role_arn
  cognito_domain_name               = module.control_plane.cognito_domain_name
  cognito_userpool_arn              = module.control_plane.cognito_userpool_arn
  cognito_userpool_id               = module.control_plane.cognito_userpool_id
  kms_key_admin_roles               = var.kms_key_admin_roles
  kms_deletion_window               = var.kms_deletion_window
  grafana_allowed_cidrs             = var.grafana_allowed_cidrs
  # allowed_access_cidr_blocks        = local.allowed_access_cidr_blocks
}


module "control_plane" {
  source = "./control_plane"

  vpc_id                 = module.vpc.vpc_id
  vpc_private_subnet_ids = module.vpc.private_subnet_ids
  # vpc_public_subnet_ids                         = module.vpc.public_subnet_ids
  vpc_default_security_group_id          = module.vpc.default_security_group_id
  vpc_cidr                               = module.vpc.vpc_cidr_block
  allowed_access_cidr_blocks             = local.allowed_access_cidr_blocks
  suffix                                 = local.project_name
  region                                 = var.region
  lambda_runtime                         = var.lambda_runtime
  aws_htc_ecr                            = local.aws_htc_ecr
  ddb_state_table                        = local.ddb_state_table
  sqs_queue                              = local.sqs_queue
  sqs_dlq                                = local.sqs_dlq
  s3_bucket                              = local.s3_bucket
  grid_storage_service                   = var.grid_storage_service
  task_queue_service                     = var.task_queue_service
  task_queue_config                      = var.task_queue_config
  state_table_service                    = var.state_table_service
  state_table_config                     = var.state_table_config
  task_input_passed_via_external_storage = var.task_input_passed_via_external_storage
  lambda_name_ttl_checker                = local.lambda_name_ttl_checker
  lambda_name_submit_tasks               = local.lambda_name_submit_tasks
  lambda_name_get_results                = local.lambda_name_get_results
  lambda_name_cancel_tasks               = local.lambda_name_cancel_tasks
  # ec2 backend has no in-cluster InfluxDB; the control-plane Lambdas must also run with
  # metrics off or they crash at import initializing the InfluxDB perf tracker (502).
  metrics_are_enabled                           = local.metrics_are_enabled_effective
  metrics_submit_tasks_lambda_connection_string = var.metrics_submit_tasks_lambda_connection_string
  metrics_get_results_lambda_connection_string  = var.metrics_get_results_lambda_connection_string
  metrics_cancel_tasks_lambda_connection_string = var.metrics_cancel_tasks_lambda_connection_string
  metrics_ttl_checker_lambda_connection_string  = var.metrics_ttl_checker_lambda_connection_string
  error_log_group                               = local.error_log_group
  error_logging_stream                          = local.error_logging_stream
  dynamodb_table_read_capacity                  = var.dynamodb_default_read_capacity
  dynamodb_table_write_capacity                 = var.dynamodb_default_write_capacity
  dynamodb_billing_mode                         = var.dynamodb_billing_mode
  dynamodb_autoscaling_enabled                  = var.dynamodb_autoscaling_enabled
  dynamodb_gsi_index_table_write_capacity       = var.dynamodb_default_write_capacity
  dynamodb_gsi_index_table_read_capacity        = var.dynamodb_default_read_capacity
  dynamodb_gsi_ttl_table_write_capacity         = var.dynamodb_default_write_capacity
  dynamodb_gsi_ttl_table_read_capacity          = var.dynamodb_default_read_capacity
  nlb_influxdb                                  = try(module.compute_plane[0].nlb_influxdb, "")
  cluster_name                                  = local.cluster_name
  api_gateway_version                           = var.api_gateway_version
  eks_managed_node_groups                       = try(module.compute_plane[0].eks_managed_node_groups, {})
  enable_node_drainer                           = var.worker_backend == "eks"
  enable_scaling_metrics                        = var.worker_backend == "eks"
  tasks_queue_name                              = local.tasks_queue_name
  namespace_metrics                             = var.namespace_metrics
  dimension_name_metrics                        = var.dimension_name_metrics
  lambda_name_scaling_metrics                   = local.lambda_name_scaling_metrics
  lambda_name_node_drainer                      = local.lambda_name_node_drainer
  period_metrics                                = var.period_metrics
  metric_name                                   = local.metrics_name
  metrics_event_rule_time                       = var.metrics_event_rule_time
  graceful_termination_delay                    = var.graceful_termination_delay
  lambda_configuration_s3_source                = try(var.agent_configuration.lambda.s3_source, local.default_agent_configuration.lambda.s3_source)
  lambda_configuration_s3_source_kms_key_arn    = try(var.agent_configuration.lambda.s3_source_kms_key_arn, local.default_agent_configuration.lambda.s3_source_kms_key_arn)
  kms_key_admin_roles                           = var.kms_key_admin_roles
  kms_deletion_window                           = var.kms_deletion_window


  depends_on = [
    module.vpc,
  ]
}


module "htc_agent" {
  source                             = "./htc-agent"
  count                              = var.worker_backend == "eks" ? 1 : 0
  region                             = var.region
  agent_chart_url                    = lookup(var.agent_configuration, "agent_chart_url", local.default_agent_configuration.agent_chart_url)
  termination_grace_period           = var.graceful_termination_delay
  suffix                             = local.project_name
  agent_name                         = var.htc_agent_name
  htc_agent_permissions_policy_arn   = module.control_plane.htc_agent_permissions_policy_arn
  eks_oidc_provider_arn              = try(module.compute_plane[0].oidc_provider_arn, "")
  max_htc_agents                     = var.max_htc_agents
  min_htc_agents                     = var.min_htc_agents
  htc_agent_target_value             = var.htc_agent_target_value
  namespace_metrics                  = var.namespace_metrics
  dimension_name_metrics             = var.dimension_name_metrics
  dimension_value_metrics            = local.cluster_name
  metric_name                        = local.metrics_name
  agent_image_tag                    = try(var.agent_configuration.agent.tag, local.default_agent_configuration.agent.tag)
  agent_image_repository             = try(var.agent_configuration.agent.image, local.default_agent_configuration.agent.image)
  agent_pull_policy                  = try(var.agent_configuration.agent.pullPolicy, local.default_agent_configuration.agent.pullPolicy)
  agent_min_cpu                      = try(var.agent_configuration.agent.minCPU, local.default_agent_configuration.agent.minCPU)
  agent_max_cpu                      = try(var.agent_configuration.agent.maxCPU, local.default_agent_configuration.agent.maxCPU)
  agent_min_memory                   = try(var.agent_configuration.agent.minMemory, local.default_agent_configuration.agent.minMemory)
  agent_max_memory                   = try(var.agent_configuration.agent.maxMemory, local.default_agent_configuration.agent.maxMemory)
  get_layer_image_tag                = try(var.agent_configuration.get_layer.tag, local.default_agent_configuration.get_layer.tag)
  get_layer_image_repository         = try(var.agent_configuration.get_layer.image, local.default_agent_configuration.get_layer.image)
  get_layer_pull_policy              = try(var.agent_configuration.get_layer.pullPolicy, local.default_agent_configuration.get_layer.pullPolicy)
  lambda_image_tag                   = try(var.agent_configuration.lambda.runtime, local.default_agent_configuration.lambda.runtime)
  lambda_image_repository            = try(var.agent_configuration.lambda.image, local.default_agent_configuration.lambda.image)
  lambda_pull_policy                 = try(var.agent_configuration.lambda.pullPolicy, local.default_agent_configuration.lambda.pullPolicy)
  lambda_min_cpu                     = try(var.agent_configuration.lambda.minCPU, local.default_agent_configuration.lambda.minCPU)
  lambda_max_cpu                     = try(var.agent_configuration.lambda.maxCPU, local.default_agent_configuration.lambda.maxCPU)
  lambda_min_memory                  = try(var.agent_configuration.lambda.minMemory, local.default_agent_configuration.lambda.minMemory)
  lambda_max_memory                  = try(var.agent_configuration.lambda.maxMemory, local.default_agent_configuration.lambda.maxMemory)
  lambda_handler_file_name           = try(var.agent_configuration.lambda.lambda_handler_file_name, local.default_agent_configuration.lambda.lambda_handler_file_name)
  lambda_handler_function_name       = try(var.agent_configuration.lambda.lambda_handler_function_name, local.default_agent_configuration.lambda.lambda_handler_function_name)
  lambda_configuration_function_name = try(var.agent_configuration.lambda.function_name, local.default_agent_configuration.lambda.function_name)
  lambda_configuration_s3_source     = try(var.agent_configuration.lambda.s3_source, local.default_agent_configuration.lambda.s3_source)
  test_agent_image_tag               = try(var.agent_configuration.test.tag, local.default_agent_configuration.test.tag)
  test_pull_policy                   = try(var.agent_configuration.test.pullPolicy, local.default_agent_configuration.test.pullPolicy)
  test_agent_image_repository        = try(var.agent_configuration.test.image, local.default_agent_configuration.test.image)

  depends_on = [
    module.vpc,
    module.compute_plane,
    module.control_plane,
    kubernetes_config_map.htcagentconfig
  ]
}


# ===========================================================================
# EC2 worker backend (worker_backend = "ec2")
# ===========================================================================

# Agent runtime config delivered to EC2 workers via SSM SecureString (the EKS path
# uses the kubernetes_config_map instead). metrics are forced off for ec2 (no InfluxDB).
resource "aws_ssm_parameter" "agent_config" {
  count = var.worker_backend == "ec2" ? 1 : 0

  name   = "/htc/${local.project_name}/agent_config"
  type   = "SecureString"
  tier   = "Advanced" # the ~45-key blob can exceed the 4 KB standard-tier limit
  key_id = module.control_plane.htc_data_bucket_key_arn
  value  = local.agent_config
}

# Stage the docker-compose plugin binary in S3 (private-subnet instances cannot reach
# github). The apply host needs internet for the curl; the data bucket is readable by the
# instance profile (agent policy grants s3:GetObject + kms:Decrypt on it).
resource "null_resource" "fetch_compose_plugin" {
  count = var.worker_backend == "ec2" ? 1 : 0

  triggers = {
    version = var.ec2_compose_plugin_version
  }

  provisioner "local-exec" {
    command = "mkdir -p '${path.module}/.cache' && curl -sSL 'https://github.com/docker/compose/releases/download/${var.ec2_compose_plugin_version}/docker-compose-linux-x86_64' -o '${path.module}/.cache/docker-compose'"
  }
}

resource "aws_s3_object" "compose_plugin" {
  count = var.worker_backend == "ec2" ? 1 : 0

  bucket     = module.control_plane.htc_data_bucket_name
  key        = "ec2-worker/docker-compose"
  source     = "${path.module}/.cache/docker-compose"
  kms_key_id = module.control_plane.htc_data_bucket_key_arn

  depends_on = [null_resource.fetch_compose_plugin]
}

module "compute_plane_ec2" {
  source = "./compute_plane_ec2"
  count  = var.worker_backend == "ec2" ? 1 : 0

  region                           = var.region
  suffix                           = local.project_name
  cluster_name                     = local.cluster_name
  aws_htc_ecr                      = local.aws_htc_ecr
  image_tag                        = local.project_name
  vpc_id                           = module.vpc.vpc_id
  vpc_private_subnet_ids           = module.vpc.private_subnet_ids
  htc_agent_permissions_policy_arn = module.control_plane.htc_agent_permissions_policy_arn
  ssm_config_parameter_arn         = aws_ssm_parameter.agent_config[0].arn
  ssm_config_parameter_name        = aws_ssm_parameter.agent_config[0].name
  ssm_config_kms_key_arn           = module.control_plane.htc_data_bucket_key_arn
  lambda_configuration_s3_source   = try(var.agent_configuration.lambda.s3_source, local.default_agent_configuration.lambda.s3_source)
  compose_plugin_s3_uri            = "s3://${module.control_plane.htc_data_bucket_name}/ec2-worker/docker-compose"
  pair_cpu                         = var.ec2_worker_vcpus
  pair_memory                      = var.ec2_worker_memory_mb
  kms_key_admin_arns               = [data.aws_caller_identity.current.arn]

  # Per-container hard limits come from the SAME agent_configuration source as the EKS
  # (htc-agent) backend, so resources are defined in one place for both backends.
  agent_max_cpu     = try(var.agent_configuration.agent.maxCPU, local.default_agent_configuration.agent.maxCPU)
  agent_max_memory  = try(var.agent_configuration.agent.maxMemory, local.default_agent_configuration.agent.maxMemory)
  lambda_max_cpu    = try(var.agent_configuration.lambda.maxCPU, local.default_agent_configuration.lambda.maxCPU)
  lambda_max_memory = try(var.agent_configuration.lambda.maxMemory, local.default_agent_configuration.lambda.maxMemory)

  depends_on = [
    module.vpc,
    module.control_plane,
    aws_s3_object.compose_plugin,
  ]
}

# ORB orchestrator: the fleet-scaling orchestrator (create/status/terminate EC2 capacity).
# The worker cloud-init is no longer delivered via SSM: the orchestrator module bakes it (and the
# subnet/SG/profile/AMI + instance selection) into the rendered ORB template at deploy time.
module "orb_orchestrator" {
  source = "./orb_orchestrator"
  count  = var.worker_backend == "ec2" ? 1 : 0

  region                      = var.region
  suffix                      = local.project_name
  aws_htc_ecr                 = local.aws_htc_ecr
  lambda_runtime              = var.lambda_runtime
  table_prefix                = "orb-${local.project_name}"
  worker_instance_role_arn    = module.compute_plane_ec2[0].instance_role_arn
  worker_instance_profile_arn = module.compute_plane_ec2[0].instance_profile_arn
  worker_subnet_ids           = module.vpc.private_subnet_ids
  worker_security_group_id    = module.compute_plane_ec2[0].worker_security_group_id
  worker_ami_id               = module.compute_plane_ec2[0].worker_ami_id
  worker_user_data_plain      = module.compute_plane_ec2[0].worker_user_data_plain
  orb_template_id             = var.orb_template_id
  pair_cpu                    = var.ec2_worker_vcpus
  pair_memory                 = var.ec2_worker_memory_mb
  max_instances               = var.orb_max_instances
  kms_key_admin_arns          = [data.aws_caller_identity.current.arn]
  kms_deletion_window         = var.kms_deletion_window
}

# Capacity controller: EventBridge-scheduled reconciler that drives the orchestrator from backlog.
module "capacity_controller" {
  source = "./capacity_controller"
  count  = var.worker_backend == "ec2" ? 1 : 0

  region                     = var.region
  suffix                     = local.project_name
  lambda_runtime             = var.lambda_runtime
  aws_htc_ecr                = local.aws_htc_ecr
  orchestrator_function_name = module.orb_orchestrator[0].function_name
  orchestrator_function_arn  = module.orb_orchestrator[0].function_arn
  orb_template_id            = var.orb_template_id
  task_queue_service         = var.task_queue_service
  task_queue_config          = var.task_queue_config
  tasks_queue_name           = local.tasks_queue_name
  sqs_queue                  = local.sqs_queue
  sqs_kms_key_arn            = module.control_plane.htc_task_queue_key_arn
  error_log_group            = local.error_log_group
  error_logging_stream       = local.error_logging_stream
  pair_cpu                   = var.ec2_worker_vcpus
  pair_memory                = var.ec2_worker_memory_mb
  min_vcpus                  = var.orb_min_vcpus
  max_vcpus                  = var.orb_max_vcpus
  target_pending_per_pair    = var.orb_target_pending_per_pair
  control_interval           = var.orb_control_interval
  drain_deadline_sec         = var.ec2_drain_deadline_sec
  state_table_name           = local.ddb_state_table
  state_table_arn            = "arn:${data.aws_partition.current.partition}:dynamodb:${var.region}:${local.account_id}:table/${local.ddb_state_table}"
  state_table_kms_key_arn    = module.control_plane.htc_dynamodb_table_key_arn
  state_table_service        = var.state_table_service
  state_table_config         = var.state_table_config
  kms_key_admin_arns         = [data.aws_caller_identity.current.arn]
  kms_deletion_window        = var.kms_deletion_window
}


# ---------------------------------------------------------------------------
# State moves: compute_plane and htc_agent became counted modules (count=1 on
# the eks backend). These moved{} blocks keep an existing EKS state from
# planning a destroy/recreate when upgrading to the selectable-backend layout.
# ---------------------------------------------------------------------------
moved {
  from = module.compute_plane
  to   = module.compute_plane[0]
}

moved {
  from = module.htc_agent
  to   = module.htc_agent[0]
}

moved {
  from = kubernetes_config_map.htcagentconfig
  to   = kubernetes_config_map.htcagentconfig[0]
}
