import * as cdk from "aws-cdk-lib"
import * as iam from "aws-cdk-lib/aws-iam";
import * as eks from "aws-cdk-lib/aws-eks";
import * as fs from "fs" ;

export interface IWorkerGroup {
  name: string;
  override_instance_types: [string];
  spot_instance_pools: number;
  asg_min_size: number;
  asg_max_size: number;
  asg_desired_capacity: number;
  on_demand_base_capacity: number;
}

export interface IWorkerInfo {
  configs: IWorkerGroup;
  role: iam.IRole;
  nodegroup: eks.Nodegroup;
}

export interface IInputRole {
  rolearn: string;
  username: string;
  groups: string[];
}

export interface IAgentContainerConfig {
  image: string
  tag: string
  pullPolicy: string;
  minCPU: number;
  maxCPU: number;
  maxMemory: number;
  minMemory: number;
}

export interface IGetLayerContainerConfig {
  image: string
  tag: string
  pullPolicy: string;
  lambda_layer_type: string;
}

export interface ITestContainerConfig {
  image: string
  tag: string
  pullPolicy: string;
}


export interface ILambdaContainerConfig {
  image: string
  runtime: string
  pullPolicy: string;
  minCPU: number;
  maxCPU: number;
  maxMemory: number;
  minMemory: number;
  storage: string;
  location: string;
  function_name: string;
  layer_name: string;
  lambda_handler_file_name: string;
  lambda_handler_function_name: string;
  layer_version: string;
  region: string;
}

export interface IAgentDeploymentConfig {
  agent_chart_url: string;
  agent_container: IAgentContainerConfig;
  lambda_container: ILambdaContainerConfig;
  get_layer: IGetLayerContainerConfig;
  test: ITestContainerConfig;

}

export interface IGrafanaConfig {
  downloadDashboardsImage_tag: string;
  grafana_tag: string;
  initChownData_tag: string;
  sidecar_tag: string;
  admin_password: string;
}

export interface IPrometheusConfig {
  node_exporter_tag: string;
  server_tag: string;
  alertmanager_tag: string;
  kube_state_metrics_tag: string;
  pushgateway_tag: string;
  configmap_reload_tag: string;
}


export interface IHTCGridConfig {
  empty_task_queue_backoff_timeout_sec: number;
  agent_task_visibility_timeout_sec: number;
  task_ttl_expiration_offset_sec: number;
  task_ttl_refresh_interval_sec: number;
  work_proc_status_pull_interval_sec : number;
  aws_htc_ecr: string;
  project_name: string;
  region: string;
  grafana_admin_password: string;
  cluster_name: string;
  ddb_state_table: string;
  sqs_queue: string;
  tasks_queue_name: string;
  sqs_dlq: string;
  lambda_name_get_results: string;
  lambda_name_submit_tasks: string;
  lambda_name_cancel_tasks: string;
  lambda_name_ttl_checker: string;
  lambda_name_scaling_metric: string;
  average_period: string;
  period_metrics: string;
  metrics_name: string;
  metrics_event_rule_time: string;
  namespace_metrics: string;
  dimension_name_metrics: string
  htc_agent_name: string;
  htc_agent_namespace: string;
  min_htc_agents: number;
  max_htc_agents: number;
  htc_agent_target_value: number;
  graceful_termination_delay: number;
  eks_worker_groups: IWorkerGroup[];
  aws_xray_daemon_version: string;
  config_name: string;
  s3_bucket: string;
  htc_path_logs: string;
  error_log_group: string;
  error_logging_stream: string;
  agent_configuration: IAgentDeploymentConfig;
  grafana_configuration: IGrafanaConfig;
  prometheus_configuration: IPrometheusConfig;
  public_subnets: number;
  private_subnets: number;
  enable_private_subnet: boolean;
  kubernetes_version: string;
  k8s_ca_version: string;
  cwa_version:string;
  state_table_service: string;
  state_table_config: string;
  aws_node_termination_handler_version: string;
  cw_agent_version: string;
  fluentbit_version: string;
  lambda_runtime: string;
  input_roles: IInputRole[];
  vpc_cidr: string;
  grid_storage_service: string;
  task_queue_service: string;
  task_queue_config: string;
  task_input_passed_via_external_storage: number;
  metrics_are_enabled: string;
  metrics_submit_tasks_lambda_connection_string: string;
  metrics_get_results_lambda_connection_string: string;
  metrics_cancel_tasks_lambda_connection_string: string;
  metrics_ttl_checker_lambda_connection_string: string;
  dynamodb_table_read_capacity: string;
  dynamodb_table_write_capacity: string;
  dynamodb_gsi_index_table_write_capacity: number;
  dynamodb_gsi_index_table_read_capacity: number;
  dynamodb_gsi_ttl_table_write_capacity: number;
  dynamodb_gsi_ttl_table_read_capacity: number;
  dynamodb_gsi_parent_table_write_capacity: number;
  dynamodb_gsi_parent_table_read_capacity: number;
  dynamodb_table_defaul_read_capacity: number,
  dynamodb_table_default_write_capacity: number,
  dynamodb_results_pull_interval_sec: number,
  agent_use_congestion_control: string;
  api_gateway_version: string ;
  influxdb_version: string ;
  enable_xray: string;

}

function makeid(length:number) {
  let result           = '';
  let characters       = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let charactersLength = characters.length;
  for ( let i = 0; i < length; i++ ) {
    result += characters.charAt(Math.floor(Math.random() *
        charactersLength));
  }
  return result;
}

export interface IGetLayerContainerConfig {

}

export interface ITestContainerConfig {

}

export function loadConfig(app: cdk.App, configFileName: string, account:string, region: string) {
  const rawConfig = fs.readFileSync(configFileName, 'utf8')
  const JSONconfig= JSON.parse(rawConfig)
  const project_name : string = JSONconfig?.project_name || makeid(5)
  const repositoryName: string =  JSONconfig?.aws_htc_ecr || `${account}.dkr.ecr.${region}.amazonaws.com`
  const config: IHTCGridConfig = <IHTCGridConfig>{
    agent_configuration: {
      agent_chart_url: JSONconfig?.agent_configuration?.agent_chart_url || app.node.tryGetContext("agent_chart_url"),
      agent_container: {
        image: JSONconfig?.agent_configuration?.agent?.image || `${repositoryName}/awshpc-lambda`,
        tag: JSONconfig?.agent_configuration?.agent?.tag || project_name,
        pullPolicy: JSONconfig?.agent_configuration?.agent?.pullPolicy || app.node.tryGetContext("agent_pull_policy"),
        minCPU: JSONconfig?.agent_configuration?.agent?.minCPU || app.node.tryGetContext("agent_min_cpu"),
        maxCPU: JSONconfig?.agent_configuration?.agent?.maxCPU || app.node.tryGetContext("agent_max_cpu"),
        maxMemory: JSONconfig?.agent_configuration?.agent?.maxMemory || app.node.tryGetContext("agent_max_memory"),
        minMemory: JSONconfig?.agent_configuration?.agent?.minMemory || app.node.tryGetContext("agent_min_memory"),
      },
      lambda_container: {
        image: JSONconfig?.agent_configuration?.lambda?.image || `${repositoryName}/lambda`,
        runtime: JSONconfig?.agent_configuration?.lambda?.runtime || app.node.tryGetContext("lambda_image_tag"),
        pullPolicy: JSONconfig?.agent_configuration?.lambda?.pullPolicy || app.node.tryGetContext("lambda_pull_policy"),
        minCPU: JSONconfig?.agent_configuration?.lambda?.minCPU || app.node.tryGetContext("lambda_min_cpu"),
        maxCPU: JSONconfig?.agent_configuration?.lambda?.maxCPU || app.node.tryGetContext("lambda_max_cpu"),
        maxMemory: JSONconfig?.agent_configuration?.lambda?.maxMemory || app.node.tryGetContext("lambda_max_memory"),
        minMemory: JSONconfig?.agent_configuration?.lambda?.minMemory || app.node.tryGetContext("lambda_min_memory"),
        location: JSONconfig?.agent_configuration?.lambda?.location || app.node.tryGetContext("lambda_configuration_location"),
        function_name: JSONconfig?.agent_configuration?.lambda?.function_name || app.node.tryGetContext("lambda_configuration_function_name"),
        lambda_handler_file_name: JSONconfig?.agent_configuration?.lambda?.lambda_handler_file_name || app.node.tryGetContext("lambda_handler_file_name"),
        lambda_handler_function_name: JSONconfig?.agent_configuration?.lambda?.lambda_handler_function_name || app.node.tryGetContext("lambda_handler_file_name"),
      },
      get_layer: {
        image: JSONconfig?.agent_configuration?.get_layer?.image || `${repositoryName}/lambda-init`,
        tag: JSONconfig?.agent_configuration?.get_layer?.tag || project_name,
        pullPolicy: JSONconfig?.agent_configuration?.get_layer?.pullPolicy || app.node.tryGetContext("get_layer_pull_policy"),
        lambda_layer_type: JSONconfig?.agent_configuration?.get_layer?.lambda_layer_type || app.node.tryGetContext("lambda_configuration_storage_type")
      },
      test: {
        image: JSONconfig?.agent_configuration?.test?.image || `${repositoryName}/submitter`,
        tag: JSONconfig?.agent_configuration?.test?.tag || project_name,
        pullPolicy: JSONconfig?.agent_configuration?.test?.pullPolicy || app.node.tryGetContext("test_pull_policy"),
      }
    },
    agent_use_congestion_control: JSONconfig?.agent_use_congestion_control || app.node.tryGetContext("agent_use_congestion_control"),
    api_gateway_version: JSONconfig?.api_gateway_version || app.node.tryGetContext("api_gateway_version"),
    average_period: JSONconfig?.average_period || app.node.tryGetContext("average_period"),
    aws_htc_ecr: repositoryName,
    aws_node_termination_handler_version: JSONconfig?.aws_node_termination_handler_version || app.node.tryGetContext("aws_node_termination_handler_version"),
    aws_xray_daemon_version: JSONconfig?.aws_xray_daemon_version || app.node.tryGetContext("aws_xray_daemon_version"),
    cluster_name: `${JSONconfig?.cluster_name || app.node.tryGetContext("cluster_name")}-${project_name}`,
    config_name: `${JSONconfig?.config_name || app.node.tryGetContext("config_name")}-${project_name}`,
    cw_agent_version: JSONconfig?.cw_agent_version || app.node.tryGetContext("cw_agent_version"),
    cwa_version: JSONconfig?.cwa_version || app.node.tryGetContext("cwa_version"),
    ddb_state_table: `${JSONconfig?.ddb_state_table || app.node.tryGetContext("ddb_state_table")}-${project_name}`,
    dimension_name_metrics: JSONconfig?.dimension_name_metrics || app.node.tryGetContext("dimension_name_metrics"),
    dynamodb_gsi_index_table_read_capacity: JSONconfig?.dynamodb_default_read_capacity || app.node.tryGetContext("dynamodb_default_read_capacity"),
    dynamodb_gsi_index_table_write_capacity: JSONconfig?.dynamodb_default_write_capacity || app.node.tryGetContext("dynamodb_default_write_capacity"),
    dynamodb_gsi_parent_table_read_capacity: JSONconfig?.dynamodb_default_read_capacity || app.node.tryGetContext("dynamodb_default_read_capacity"),
    dynamodb_gsi_parent_table_write_capacity: JSONconfig?.dynamodb_default_write_capacity || app.node.tryGetContext("dynamodb_default_write_capacity"),
    dynamodb_gsi_ttl_table_read_capacity: JSONconfig?.dynamodb_default_read_capacity || app.node.tryGetContext("dynamodb_default_read_capacity"),
    dynamodb_gsi_ttl_table_write_capacity: JSONconfig?.dynamodb_default_write_capacity || app.node.tryGetContext("dynamodb_default_write_capacity"),
    dynamodb_table_read_capacity: JSONconfig?.dynamodb_default_read_capacity || app.node.tryGetContext("dynamodb_default_read_capacity"),
    dynamodb_table_write_capacity: JSONconfig?.dynamodb_default_write_capacity || app.node.tryGetContext("dynamodb_default_write_capacity"),
    dynamodb_table_defaul_read_capacity: JSONconfig?.dynamodb_default_read_capacity || app.node.tryGetContext("dynamodb_default_read_capacity"),
    dynamodb_table_default_write_capacity: JSONconfig?.dynamodb_default_write_capacity || app.node.tryGetContext("dynamodb_default_write_capacity"),
    eks_worker_groups: JSONconfig?.eks_worker_groups ,
    enable_private_subnet: JSONconfig?.enable_private_subnet || app.node.tryGetContext("enable_private_subnet"),
    error_log_group: `${JSONconfig?.error_log_group || app.node.tryGetContext("error_log_group")}-${project_name}`,
    error_logging_stream: `${JSONconfig?.error_logging_stream || app.node.tryGetContext("error_logging_stream")}-${project_name}`,
    fluentbit_version: JSONconfig?.fluentbit_version || app.node.tryGetContext("fluentbit_version"),
    graceful_termination_delay: JSONconfig?.graceful_termination_delay || app.node.tryGetContext("graceful_termination_delay"),
    grafana_admin_password: JSONconfig?.grafana_admin_password || makeid(12),
    grafana_configuration: {
      downloadDashboardsImage_tag: JSONconfig?.grafana_configuration?.downloadDashboardsImage_tag || app.node.tryGetContext("grafana_configuration_downloadDashboardsImage_tag"),
      grafana_tag: JSONconfig?.grafana_configuration?.grafana_tag || app.node.tryGetContext("grafana_configuration_grafana_tag"),
      initChownData_tag: JSONconfig?.grafana_configuration?.initChownData_tag || app.node.tryGetContext("grafana_configuration_initChownData_tag"),
      sidecar_tag: JSONconfig?.grafana_configuration?.sidecar_tag || app.node.tryGetContext("grafana_configuration_sidecar_tag"),
      admin_password: JSONconfig?.grafana_configuration?.admin_password || app.node.tryGetContext("grafana_configuration_admin_password")
    },
    grid_storage_service: JSONconfig?.grid_storage_service || app.node.tryGetContext("grid_storage_service"),
    htc_agent_name: JSONconfig?.htc_agent_name || app.node.tryGetContext("htc_agent_name"),
    htc_agent_namespace: JSONconfig?.htc_agent_namespace || app.node.tryGetContext("htc_agent_namespace"),
    htc_agent_target_value: JSONconfig?.htc_agent_target_value || app.node.tryGetContext("htc_agent_target_value"),
    htc_path_logs: JSONconfig?.htc_path_logs || app.node.tryGetContext("htc_path_logs"),
    influxdb_version: JSONconfig?.influxdb_version || app.node.tryGetContext("influxdb_version"),
    input_roles: JSONconfig?.input_role || [],
    k8s_ca_version: JSONconfig?.k8s_ca_version || app.node.tryGetContext("k8s_ca_version"),
    kubernetes_version: JSONconfig?.kubernetes_version || app.node.tryGetContext("kubernetes_version"),
    lambda_name_cancel_tasks: `${JSONconfig?.lambda_name_cancel_tasks || app.node.tryGetContext("lambda_name_cancel_tasks")}-${project_name}`,
    lambda_name_get_results: `${JSONconfig?.lambda_name_get_results || app.node.tryGetContext("lambda_name_get_results")}-${project_name}`,
    lambda_name_scaling_metric: `${JSONconfig?.lambda_name_scaling_metric || app.node.tryGetContext("lambda_name_scaling_metric")}-${project_name}`,
    lambda_name_submit_tasks: `${JSONconfig?.lambda_name_submit_tasks || app.node.tryGetContext("lambda_name_submit_tasks")}-${project_name}`,
    lambda_name_ttl_checker: `${JSONconfig?.lambda_name_ttl_checker || app.node.tryGetContext("lambda_name_ttl_checker")}-${project_name}`,
    lambda_runtime: JSONconfig?.lambda_runtime || app.node.tryGetContext("lambda_runtime"),
    max_htc_agents: JSONconfig?.max_htc_agents || app.node.tryGetContext("max_htc_agents"),
    metrics_are_enabled: JSONconfig?.metrics_are_enabled || app.node.tryGetContext("metrics_are_enabled"),
    metrics_cancel_tasks_lambda_connection_string: JSONconfig?.metrics_cancel_tasks_lambda_connection_string || app.node.tryGetContext("metrics_cancel_tasks_lambda_connection_string"),
    metrics_event_rule_time: JSONconfig?.metrics_event_rule_time || app.node.tryGetContext("metrics_event_rule_time"),
    metrics_get_results_lambda_connection_string: JSONconfig?.metrics_get_results_lambda_connection_string || app.node.tryGetContext("metrics_get_results_lambda_connection_string"),
    metrics_name: `${JSONconfig?.metrics_name || app.node.tryGetContext("metrics_name")}-${project_name}`,
    metrics_submit_tasks_lambda_connection_string: JSONconfig?.metrics_submit_tasks_lambda_connection_string || app.node.tryGetContext("metrics_submit_tasks_lambda_connection_string"),
    metrics_ttl_checker_lambda_connection_string: JSONconfig?.metrics_ttl_checker_lambda_connection_string || app.node.tryGetContext("metrics_ttl_checker_lambda_connection_string"),
    min_htc_agents: JSONconfig?.min_htc_agents || app.node.tryGetContext("min_htc_agents"),
    namespace_metrics: JSONconfig?.namespace_metrics || app.node.tryGetContext("namespace_metrics"),
    period_metrics: JSONconfig?.period_metrics || app.node.tryGetContext("period_metrics"),
    private_subnets: JSONconfig?.vpc_cidr_block_private || app.node.tryGetContext("vpc_cidr_block_private"),
    project_name: project_name,
    prometheus_configuration: {
      node_exporter_tag: JSONconfig?.prometheus_configuration?.node_exporter_tag || app.node.tryGetContext("prometheus_configuration_node_exporter_tag"),
      server_tag: JSONconfig?.prometheus_configuration?.server_tag || app.node.tryGetContext("prometheus_configuration_server_tag"),
      alertmanager_tag: JSONconfig?.prometheus_configuration?.alertmanager_tag || app.node.tryGetContext("prometheus_configuration_alertmanager_tag"),
      kube_state_metrics_tag: JSONconfig?.prometheus_configuration?.kube_state_metrics_tag || app.node.tryGetContext("prometheus_configuration_kube_state_metrics_tag"),
      pushgateway_tag: JSONconfig?.prometheus_configuration?.pushgateway_tag || app.node.tryGetContext("prometheus_configuration_pushgateway_tag"),
      configmap_reload_tag: JSONconfig?.prometheus_configuration?.configmap_reload_tag || app.node.tryGetContext("prometheus_configuration_configmap_reload_tag"),
    },
    public_subnets: JSONconfig?.vpc_cidr_block_public || app.node.tryGetContext("vpc_cidr_block_public"),
    region: JSONconfig?.region || region,
    s3_bucket: `${JSONconfig?.s3_bucket || app.node.tryGetContext("s3_bucket")}-${project_name}`,
    sqs_dlq: `${JSONconfig?.sqs_dlq || app.node.tryGetContext("sqs_dlq")}-${project_name}`,
    sqs_queue: `${JSONconfig?.sqs_queue || app.node.tryGetContext("sqs_queue")}-${project_name}`,
    state_table_config: JSONconfig?.state_table_config || app.node.tryGetContext("state_table_config"),
    state_table_service: JSONconfig?.state_table_service || app.node.tryGetContext("state_table_service"),
    task_input_passed_via_external_storage: JSONconfig?.task_input_passed_via_external_storage || app.node.tryGetContext("task_input_passed_via_external_storage"),
    task_queue_config: JSONconfig?.task_queue_config || app.node.tryGetContext("task_queue_config"),
    task_queue_service: JSONconfig?.task_queue_service || app.node.tryGetContext("task_queue_service"),
    tasks_queue_name: `${JSONconfig?.sqs_queue || app.node.tryGetContext("sqs_queue")}-${project_name}__0`,
    vpc_cidr: JSONconfig?.api_gateway_version || app.node.tryGetContext("api_gateway_version"),
    empty_task_queue_backoff_timeout_sec: JSONconfig?.empty_task_queue_backoff_timeout_sec || app.node.tryGetContext("empty_task_queue_backoff_timeout_sec"),
    agent_task_visibility_timeout_sec: JSONconfig?.agent_task_visibility_timeout_sec || app.node.tryGetContext("agent_task_visibility_timeout_sec"),
    task_ttl_expiration_offset_sec: JSONconfig?.task_ttl_expiration_offset_sec || app.node.tryGetContext("task_ttl_expiration_offset_sec"),
    task_ttl_refresh_interval_sec: JSONconfig?.task_ttl_refresh_interval_sec || app.node.tryGetContext("task_ttl_refresh_interval_sec"),
    work_proc_status_pull_interval_sec : JSONconfig?.work_proc_status_pull_interval_sec || app.node.tryGetContext("work_proc_status_pull_interval_sec"),
    dynamodb_results_pull_interval_sec:JSONconfig?.dynamodb_results_pull_interval_sec || app.node.tryGetContext("dynamodb_results_pull_interval_sec"),
    enable_xray: JSONconfig?.enable_xray || app.node.tryGetContext("enable_xray")
  }
  return config ;
}