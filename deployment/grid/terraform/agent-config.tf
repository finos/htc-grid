# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


locals {
  agent_config = <<EOF
{
  "region": "${var.region}",
  "sqs_endpoint": "https://sqs.${var.region}.${local.dns_suffix}",
  "sqs_queue": "${local.sqs_queue}",
  "sqs_dlq": "${local.sqs_dlq}",
  "redis_url": "${module.control_plane.htc_data_cache_url}",
  "redis_password": "${module.control_plane.htc_data_cache_password}",
  "cluster_name": "${local.cluster_name}",
  "ddb_state_table" : "${local.ddb_state_table}",
  "empty_task_queue_backoff_timeout_sec" : ${var.empty_task_queue_backoff_timeout_sec},
  "work_proc_status_pull_interval_sec" : ${var.work_proc_status_pull_interval_sec},
  "task_ttl_expiration_offset_sec" : ${var.task_ttl_expiration_offset_sec},
  "task_ttl_refresh_interval_sec" : ${var.task_ttl_refresh_interval_sec},
  "dynamodb_results_pull_interval_sec" : ${var.dynamodb_results_pull_interval_sec},
  "agent_task_visibility_timeout_sec" : ${var.agent_task_visibility_timeout_sec},
  "task_input_passed_via_external_storage" : ${var.task_input_passed_via_external_storage},
  "lambda_name_ttl_checker": "${local.lambda_name_ttl_checker}",
  "lambda_name_submit_tasks": "${local.lambda_name_submit_tasks}",
  "lambda_name_get_results": "${local.lambda_name_get_results}",
  "lambda_name_cancel_tasks": "${local.lambda_name_cancel_tasks}",
  "s3_bucket": "${module.control_plane.htc_data_bucket_name}",
  "s3_kms_key_id": "${module.control_plane.htc_data_bucket_key_arn}",
  "grid_storage_service" : "${var.grid_storage_service}",
  "task_queue_service" : "${var.task_queue_service}",
  "task_queue_config" : "${var.task_queue_config}",
  "tasks_queue_name": "${local.tasks_queue_name}",
  "state_table_service" : "${var.state_table_service}",
  "state_table_config" : "${var.state_table_config}",
  "htc_path_logs" : "${var.htc_path_logs}",
  "error_log_group" : "${local.error_log_group}",
  "error_logging_stream" : "${local.error_logging_stream}",
  "metrics_are_enabled": "${var.metrics_are_enabled}",
  "metrics_grafana_private_ip": "influxdb.influxdb",
  "metrics_submit_tasks_lambda_connection_string": "${var.metrics_submit_tasks_lambda_connection_string}",
  "metrics_cancel_tasks_lambda_connection_string": "${var.metrics_cancel_tasks_lambda_connection_string}",
  "metrics_pre_agent_connection_string": "${var.metrics_pre_agent_connection_string}",
  "metrics_post_agent_connection_string": "${var.metrics_post_agent_connection_string}",
  "metrics_get_results_lambda_connection_string": "${var.metrics_get_results_lambda_connection_string}",
  "metrics_ttl_checker_lambda_connection_string": "${var.metrics_ttl_checker_lambda_connection_string}",
  "agent_use_congestion_control": "${var.agent_use_congestion_control}",
  "user_pool_id": "${module.control_plane.cognito_userpool_id}",
  "cognito_userpool_client_id": "${module.control_plane.cognito_userpool_client_id}",
  "public_api_gateway_url": "${module.control_plane.public_api_gateway_url}",
  "private_api_gateway_url": "${module.control_plane.private_api_gateway_url}",
  "api_gateway_key": "${module.control_plane.api_gateway_key}",
  "enable_xray" : "${var.enable_xray}"
}
EOF
}


#configmap with all the variables
resource "kubernetes_config_map" "htcagentconfig" {
  metadata {
    name      = "agent-configmap"
    namespace = var.htc_agent_namespace
  }

  data = {
    "Agent_config.tfvars.json" = local.agent_config
  }

  depends_on = [
    module.compute_plane,
    module.control_plane
  ]
}


resource "local_file" "agent_config_file" {
  content  = local.agent_config
  filename = "${path.module}/${var.agent_configuration_filename}"
}
