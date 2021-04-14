# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

data aws_caller_identity current {}

resource "random_string" "random_resources" {
    length = 5
    special = false
    upper = false
    # number = false
}

locals {
    aws_htc_ecr = var.aws_htc_ecr != "" ? var.aws_htc_ecr : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
    project_name = var.project_name != "" ? var.project_name : random_string.random_resources.result
    cluster_name = "${var.cluster_name}-${local.project_name}"
    ddb_status_table = "${var.ddb_status_table}-${local.project_name}"
    sqs_queue = "${var.sqs_queue}-${local.project_name}"
    sqs_dlq = "${var.sqs_dlq}-${local.project_name}"
    lambda_name_get_results = "${var.lambda_name_get_results}-${local.project_name}"
    lambda_name_submit_tasks = "${var.lambda_name_submit_tasks}-${local.project_name}"
    lambda_name_cancel_tasks = "${var.lambda_name_cancel_tasks}-${local.project_name}"
    lambda_name_ttl_checker = "${var.lambda_name_ttl_checker}-${local.project_name}"
    lambda_name_scaling_metric = "${var.lambda_name_scaling_metric}-${local.project_name}"
    metrics_name = "${var.metrics_name}-${local.project_name}"
    config_name = "${var.config_name}-${local.project_name}"
    s3_bucket = "${var.s3_bucket}-${local.project_name}"
    error_log_group = "${var.error_log_group}-${local.project_name}"
    error_logging_stream = "${var.error_logging_stream}-${local.project_name}"

    default_agent_configuration = {
        agent_chart_url  = "../charts"
        agent = {
            image = "${local.aws_htc_ecr}/awshpc-lambda"
            tag = local.project_name
            pullPolicy = "IfNotPresent"
            minCPU = "10"
            maxCPU = "50"
            maxMemory = "100"
            minMemory = "50"
        }
        lambda = {
            image = "${local.aws_htc_ecr}/lambda"
            runtime = "provided"
            pullPolicy = "IfNotPresent"
            minCPU = "800"
            maxCPU = "900"
            maxMemory = "3900"
            minMemory = "4096"
            storage = "S3"
            location = "s3://mock_location"
            function_name = "mock_computation"
            layer_name = "mock_computation_layer"
            lambda_handler_file_name = ""
            lambda_handler_function_name = ""
            layer_version = 1
            region = var.region
        }
        get_layer = {
            image = "${local.aws_htc_ecr}/lambda-init"
            tag = local.project_name
            pullPolicy = "IfNotPresent"
            lambda_layer_type = "S3"
        }
        test = {
            image = "${local.aws_htc_ecr}/submitter"
            tag = local.project_name
            pullPolicy = "IfNotPresent"
        }
    }
}

module "vpc" {

    source = "./vpc"
    region = var.region
    cluster_name = local.cluster_name
    private_subnets = var.vpc_cidr_block_private
    public_subnets = var.vpc_cidr_block_public
    enable_private_subnet = var.enable_private_subnet

}
module "resources" {
    source = "./resources"

    vpc_id = module.vpc.vpc_id
    vpc_private_subnet_ids = module.vpc.private_subnet_ids
    vpc_public_subnet_ids = module.vpc.public_subnet_ids
    vpc_default_security_group_id = module.vpc.default_security_group_id
    vpc_cidr = module.vpc.vpc_cidr_block
    cluster_name = local.cluster_name
    kubernetes_version = var.kubernetes_version
    k8s_ca_version = var.k8s_ca_version
    aws_htc_ecr = local.aws_htc_ecr
    cwa_version = var.cwa_version
    aws_node_termination_handler_version = var.aws_node_termination_handler
    cw_agent_version = var.cw_agent_version
    fluentbit_version = var.fluentbit_version
    suffix = local.project_name
    region = var.region
    lambda_runtime = var.lambda_runtime
    ddb_status_table = local.ddb_status_table
    sqs_queue = local.sqs_queue
    namespace_metrics = var.namespace_metrics
    dimension_name_metrics = var.dimension_name_metrics
    htc_path_logs = var.htc_path_logs
    lambda_name_scaling_metrics = local.lambda_name_scaling_metric
    period_metrics = var.period_metrics
    metric_name = local.metrics_name
    average_period = var.average_period
    metrics_event_rule_time = var.metrics_event_rule_time
    htc_agent_name = var.htc_agent_name
    htc_agent_namespace = var.htc_agent_namespace
    eks_worker_groups = var.eks_worker_groups
    max_htc_agents = var.max_htc_agents
    min_htc_agents = var.min_htc_agents
    htc_agent_target_value = var.htc_agent_target_value
    input_role = var.input_role
    graceful_termination_delay = var.graceful_termination_delay
    aws_xray_daemon_version = var.aws_xray_daemon_version
    enable_private_subnet = var.enable_private_subnet
    depends_on  = [
        module.vpc
    ]

    grafana_configuration = {
        downloadDashboardsImage_tag = var.grafana_configuration.downloadDashboardsImage_tag
        grafana_tag = var.grafana_configuration.grafana_tag
        initChownData_tag = var.grafana_configuration.initChownData_tag
        sidecar_tag = var.grafana_configuration.sidecar_tag
        admin_password = var.grafana_admin_password

    }
    prometheus_configuration = {
        node_exporter_tag = var.prometheus_configuration.node_exporter_tag
        server_tag = var.prometheus_configuration.server_tag
        alertmanager_tag = var.prometheus_configuration.alertmanager_tag
        kube_state_metrics_tag = var.prometheus_configuration.kube_state_metrics_tag
        pushgateway_tag = var.prometheus_configuration.pushgateway_tag
        configmap_reload_tag = var.prometheus_configuration.configmap_reload_tag
    }
}

module "scheduler" {
    source = "./scheduler"

    vpc_id = module.vpc.vpc_id
    vpc_private_subnet_ids = module.vpc.private_subnet_ids
    vpc_public_subnet_ids = module.vpc.public_subnet_ids
    vpc_default_security_group_id = module.vpc.default_security_group_id
    vpc_cidr = module.vpc.vpc_cidr_block
    suffix = local.project_name
    region = var.region
    lambda_runtime = var.lambda_runtime
    aws_htc_ecr = local.aws_htc_ecr
    ddb_status_table = local.ddb_status_table
    sqs_queue = local.sqs_queue
    sqs_dlq = local.sqs_dlq
    s3_bucket = local.s3_bucket
    grid_storage_service = var.grid_storage_service
    task_input_passed_via_external_storage = var.task_input_passed_via_external_storage
    lambda_name_ttl_checker = local.lambda_name_ttl_checker
    lambda_name_submit_tasks = local.lambda_name_submit_tasks
    lambda_name_get_results = local.lambda_name_get_results
    lambda_name_cancel_tasks = local.lambda_name_cancel_tasks
    metrics_are_enabled = var.metrics_are_enabled
    metrics_submit_tasks_lambda_connection_string = var.metrics_submit_tasks_lambda_connection_string
    metrics_get_results_lambda_connection_string = var.metrics_get_results_lambda_connection_string
    metrics_cancel_tasks_lambda_connection_string = var.metrics_cancel_tasks_lambda_connection_string
    metrics_ttl_checker_lambda_connection_string = var.metrics_ttl_checker_lambda_connection_string
    error_log_group = local.error_log_group
    error_logging_stream = local.error_logging_stream
    dynamodb_table_read_capacity = var.dynamodb_default_read_capacity
    dynamodb_table_write_capacity = var.dynamodb_default_write_capacity
    dynamodb_gsi_index_table_write_capacity = var.dynamodb_default_write_capacity
    dynamodb_gsi_index_table_read_capacity = var.dynamodb_default_read_capacity
    dynamodb_gsi_ttl_table_write_capacity = var.dynamodb_default_write_capacity
    dynamodb_gsi_ttl_table_read_capacity = var.dynamodb_default_read_capacity
    dynamodb_gsi_parent_table_write_capacity = var.dynamodb_default_write_capacity
    dynamodb_gsi_parent_table_read_capacity = var.dynamodb_default_read_capacity
    agent_use_congestion_control = var.agent_use_congestion_control
    nlb_influxdb = module.resources.nlb_influxdb
    cluster_name = local.cluster_name
    cognito_userpool_arn = module.resources.cognito_userpool_arn
    api_gateway_version = var.api_gateway_version


    depends_on  = [
        module.vpc
    ]
}


module "htc_agent" {
    source = "./htc-agent"
    agent_chart_url = lookup(var.agent_configuration,"agent_chart_url",local.default_agent_configuration.agent_chart_url)
    termination_grace_period =  var.graceful_termination_delay
    agent_image_tag = lookup(lookup(var.agent_configuration,"agent",local.default_agent_configuration.agent),"tag",local.default_agent_configuration.agent.tag)
    get_layer_image_tag = lookup(lookup(var.agent_configuration,"get_layer",local.default_agent_configuration.get_layer),"tag",local.default_agent_configuration.get_layer.tag)
    lambda_image_tag = lookup(lookup(var.agent_configuration,"lambda",local.default_agent_configuration.lambda),"runtime",local.default_agent_configuration.lambda.runtime)
    test_agent_image_tag = lookup(lookup(var.agent_configuration,"test",local.default_agent_configuration.test),"tag",local.default_agent_configuration.test.tag)
    agent_name = var.htc_agent_name
    agent_min_cpu = lookup(lookup(var.agent_configuration,"agent",local.default_agent_configuration.agent),"minCPU",local.default_agent_configuration.agent.minCPU)
    agent_max_cpu = lookup(lookup(var.agent_configuration,"agent",local.default_agent_configuration.agent),"maxCPU",local.default_agent_configuration.agent.maxCPU)
    lambda_max_cpu = lookup(lookup(var.agent_configuration,"lambda",local.default_agent_configuration.lambda),"maxCPU",local.default_agent_configuration.lambda.maxCPU)
    lambda_min_cpu = lookup(lookup(var.agent_configuration,"lambda",local.default_agent_configuration.lambda),"minCPU",local.default_agent_configuration.lambda.minCPU)
    agent_min_memory = lookup(lookup(var.agent_configuration,"agent",local.default_agent_configuration.agent),"minMemory",local.default_agent_configuration.agent.minMemory)
    agent_max_memory = lookup(lookup(var.agent_configuration,"agent",local.default_agent_configuration.agent),"maxMemory",local.default_agent_configuration.agent.maxMemory)
    lambda_min_memory = lookup(lookup(var.agent_configuration,"lambda",local.default_agent_configuration.lambda),"minMemory",local.default_agent_configuration.lambda.minMemory)
    lambda_max_memory = lookup(lookup(var.agent_configuration,"lambda",local.default_agent_configuration.lambda),"maxMemory",local.default_agent_configuration.lambda.maxMemory)
    agent_pull_policy = lookup(lookup(var.agent_configuration,"agent",local.default_agent_configuration.agent),"pullPolicy",local.default_agent_configuration.agent.pullPolicy)
    lambda_pull_policy = lookup(lookup(var.agent_configuration,"lambda",local.default_agent_configuration.lambda),"pullPolicy",local.default_agent_configuration.lambda.pullPolicy)
    get_layer_pull_policy = lookup(lookup(var.agent_configuration,"get_layer",local.default_agent_configuration.get_layer),"pullPolicy",local.default_agent_configuration.get_layer.pullPolicy)
    test_pull_policy = lookup(lookup(var.agent_configuration,"test",local.default_agent_configuration.test),"pullPolicy",local.default_agent_configuration.test.pullPolicy)
    agent_image_repository = lookup(lookup(var.agent_configuration,"agent",local.default_agent_configuration.agent),"image",local.default_agent_configuration.agent.image)
    get_layer_image_repository = lookup(lookup(var.agent_configuration,"get_layer",local.default_agent_configuration.get_layer),"image",local.default_agent_configuration.get_layer.image)
    lambda_image_repository =  lookup(lookup(var.agent_configuration,"lambda",local.default_agent_configuration.lambda),"image",local.default_agent_configuration.lambda.image)
    test_agent_image_repository = lookup(lookup(var.agent_configuration,"test",local.default_agent_configuration.test),"image",local.default_agent_configuration.test.image)
    lambda_configuration_storage_type = lookup(lookup(var.agent_configuration,"get_layer",local.default_agent_configuration.lambda),"layer_type",local.default_agent_configuration.get_layer.lambda_layer_type)
    lambda_configuration_location = lookup(lookup(var.agent_configuration,"lambda",local.default_agent_configuration.lambda),"location",local.default_agent_configuration.lambda.location)
    lambda_handler_file_name = lookup(lookup(var.agent_configuration,"lambda",local.default_agent_configuration.lambda),"lambda_handler_file_name",local.default_agent_configuration.lambda.lambda_handler_file_name)
    lambda_handler_function_name = lookup(lookup(var.agent_configuration,"lambda",local.default_agent_configuration.lambda),"lambda_handler_function_name",local.default_agent_configuration.lambda.lambda_handler_function_name)
    depends_on = [
        module.resources,
        module.scheduler,
        module.vpc,
        kubernetes_config_map.htcagentconfig
    ]

}

