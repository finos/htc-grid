#!/usr/bin/env node
import * as cdk from "aws-cdk-lib"
import { VpcStack } from "../lib/vpc/vpc";
import { EksClusterStack } from "../lib/compute_plane/eks_cluster";
import { NamespacesStack } from "../lib/compute_plane/namespaces";
import { CognitoAuthStack } from "../lib/compute_plane/auth";
import { SchedulerStack } from "../lib/control_plane/scheduler";
import { HtcAgentStack } from "../lib/htc-agent/htc-agent";

import * as helper from "../lib/shared/cluster-interfaces"
var appContext = {} as any;

const tag = process.env.TAG ?? "mainline";

appContext["tag"] = tag;
appContext["project_name"] = tag;

const app = new cdk.App({
  context: appContext,
});

const account : string =
  process.env.HTCGRID_ACCOUNT_ID || process.env.CDK_DEFAULT_ACCOUNT ||
  app.account || ""
  ;
const region : string =
  process.env.HTCGRID_REGION || app.node.tryGetContext("region") || app.region;

const env = {
  account: account,
  region: region,
};

const configFileName = app.node.tryGetContext("config") || "";
const htcGridConfig = helper.loadConfig(app,configFileName,account,region)



const vpcStack = new VpcStack(app, `${tag}-VpcStack`, {
  env: env,
  project: htcGridConfig.project_name,
  clusterName: htcGridConfig.cluster_name,
  enablePrivateSubnet: htcGridConfig.enable_private_subnet,
  privateSubnets: htcGridConfig.private_subnets,
  publicSubnets: htcGridConfig.public_subnets,
});

const clusterStack = new EksClusterStack(app, `${tag}-EksClusterStack`, {
  env: env,
  vpc: vpcStack.vpc,
  vpcDefaultSg: vpcStack.defaultSecurityGroup,
  clusterName:htcGridConfig.cluster_name,
  eksWorkerGroups: htcGridConfig.eks_worker_groups,
  enablePrivateSubnet: htcGridConfig.enable_private_subnet,
  inputRoles: htcGridConfig.input_roles,
  kubernetesVersion: htcGridConfig.kubernetes_version,
});

const namespacesStack = new NamespacesStack(app, `${tag}-ClusterNamespaces`, {
  alertManagerTag: htcGridConfig.prometheus_configuration.alertmanager_tag,
  averagePeriod: htcGridConfig.average_period,
  awsForFluentBitTag: htcGridConfig.fluentbit_version,
  awsNodeTerminationHandlerTag: htcGridConfig.aws_node_termination_handler_version,
  busyboxTag: htcGridConfig.grafana_configuration.initChownData_tag,
  clusterAutoscalerTag: htcGridConfig.k8s_ca_version,
  configMapReloadTag: htcGridConfig.prometheus_configuration.configmap_reload_tag,
  curlTag: htcGridConfig.grafana_configuration.downloadDashboardsImage_tag,
  cwaTag: htcGridConfig.cwa_version,
  cwAgentTag: htcGridConfig.cw_agent_version,
  deploymentAgentName: htcGridConfig.htc_agent_name,
  deploymentNamespace: htcGridConfig.htc_agent_namespace,
  grafanaAdminPassword: htcGridConfig.grafana_configuration.admin_password,
  grafanaTag: htcGridConfig.grafana_configuration.grafana_tag,
  influxDbTag: htcGridConfig.influxdb_version,
  k8sSideCarTag: htcGridConfig.grafana_configuration.sidecar_tag,
  kubeStateMetricsTag: htcGridConfig.prometheus_configuration.kube_state_metrics_tag,
  maxReplicas: htcGridConfig.max_htc_agents,
  metricDimensionName: htcGridConfig.dimension_name_metrics,
  metricDimensionValue: htcGridConfig.cluster_name,
  metricName: htcGridConfig.metrics_name,
  metricNamespace: htcGridConfig.namespace_metrics,
  minReplicas: htcGridConfig.min_htc_agents,
  nodeExporterTag:htcGridConfig.prometheus_configuration.node_exporter_tag,
  prometheusTag: htcGridConfig.prometheus_configuration.server_tag,
  pushGatewayTag: htcGridConfig.prometheus_configuration.pushgateway_tag,
  targetValue: htcGridConfig.htc_agent_target_value,
  xRayDaemonTag: htcGridConfig.aws_xray_daemon_version,
  env: env,
  vpc: vpcStack.vpc,
  vpc_default_sg: vpcStack.defaultSecurityGroup,
  cluster: clusterStack.eksCluster
});

const authStack = new CognitoAuthStack(app, `${tag}-AuthStack`, {
  env: env,
  clusterManager: namespacesStack.clusterManager,
  projectName: htcGridConfig.project_name
});

const schedulerStack = new SchedulerStack(app, `${tag}-SchedulerStack`, {
  env: env,
  vpc: vpcStack.vpc,
  ddbConfig: htcGridConfig.state_table_config,
  ddbDefaultRead: htcGridConfig.dynamodb_table_defaul_read_capacity,
  ddbDefaultWrite: htcGridConfig.dynamodb_table_default_write_capacity,
  ddbService: htcGridConfig.state_table_service,
  ddbTableName: htcGridConfig.ddb_state_table,
  errorLogGroup: htcGridConfig.error_log_group,
  errorLoggingStream: htcGridConfig.error_logging_stream,
  gridStorageService: htcGridConfig.grid_storage_service,
  lambdaNameCancelTasks: htcGridConfig.lambda_name_cancel_tasks,
  lambdaNameGetResults: htcGridConfig.lambda_name_get_results,
  lambdaNameSubmitTasks: htcGridConfig.lambda_name_submit_tasks,
  lambdaNameTtlChecker: htcGridConfig.lambda_name_ttl_checker,
  metricsAreEnabled: htcGridConfig.metrics_are_enabled,
  metricsCancelTasksLambdaConnectionString: htcGridConfig.metrics_cancel_tasks_lambda_connection_string,
  metricsGetResultsLambdaConnectionString: htcGridConfig.metrics_get_results_lambda_connection_string,
  metricsSubmitTasksLambdaConnectionString: htcGridConfig.metrics_submit_tasks_lambda_connection_string,
  metricsTtlCheckerLambdaConnectionString: htcGridConfig.metrics_ttl_checker_lambda_connection_string,
  projectName: htcGridConfig.project_name,
  s3BucketName: htcGridConfig.s3_bucket,
  sqsDlq: htcGridConfig.sqs_dlq,
  sqsQueue: htcGridConfig.sqs_queue,
  taskConfig: htcGridConfig.task_queue_config,
  taskInputPassedViaExternalStorage: htcGridConfig.task_input_passed_via_external_storage,
  taskService: htcGridConfig.task_queue_service,
  vpc_default_sg: vpcStack.defaultSecurityGroup,
  cognito_userpool: authStack.cognito_userpool,
  eks_cluster: clusterStack.eksCluster
});

const htcStack = new HtcAgentStack(app, `${tag}-HtcAgentStack`, {
  agentDeploymentConfig: htcGridConfig.agent_configuration,
  agentTaskVisibilityTimeoutSec: htcGridConfig.agent_task_visibility_timeout_sec,
  agentUseCongestionControl: htcGridConfig.agent_use_congestion_control,
  ddbConfig: htcGridConfig.state_table_config,
  ddbDefaultRead: htcGridConfig.dynamodb_table_defaul_read_capacity,
  ddbDefaultWrite: htcGridConfig.dynamodb_table_default_write_capacity,
  ddbService: htcGridConfig.state_table_service,
  ddbTableName: htcGridConfig.ddb_state_table,
  deploymentAgentName: htcGridConfig.htc_agent_name,
  deploymentNamespace: htcGridConfig.htc_agent_namespace,
  dynamodbResultsPullIntervalSec: htcGridConfig.dynamodb_results_pull_interval_sec,
  emptyTaskQueueBackoffTimeoutSec: htcGridConfig.empty_task_queue_backoff_timeout_sec,
  enableXRay: htcGridConfig.enable_xray,
  errorLogGroup: htcGridConfig.error_log_group,
  errorLoggingStream: htcGridConfig.error_logging_stream,
  gridStorageService: htcGridConfig.grid_storage_service,
  htcPathLogs: htcGridConfig.htc_path_logs,
  lambdaNameCancelTasks: htcGridConfig.lambda_name_cancel_tasks,
  lambdaNameGetResults: htcGridConfig.lambda_name_get_results,
  lambdaNameSubmitTasks: htcGridConfig.lambda_name_submit_tasks,
  lambdaNameTtlChecker: htcGridConfig.lambda_name_ttl_checker,
  maxReplicas: htcGridConfig.max_htc_agents,
  metricsAreEnabled: htcGridConfig.metrics_are_enabled,
  metricsCancelTasksLambdaConnectionString: htcGridConfig.metrics_cancel_tasks_lambda_connection_string,
  metricsGetResultsLambdaConnectionString: htcGridConfig.metrics_get_results_lambda_connection_string,
  metricsPostAgentTasksLambdaConnectionString: "",
  metricsPreAgentTasksLambdaConnectionString: "",
  metricsSubmitTasksLambdaConnectionString: htcGridConfig.metrics_submit_tasks_lambda_connection_string,
  metricsTtlCheckerLambdaConnectionString: htcGridConfig.metrics_ttl_checker_lambda_connection_string,
  minReplicas: htcGridConfig.min_htc_agents,
  projectName: htcGridConfig.project_name,
  s3BucketName: htcGridConfig.s3_bucket,
  sqsDlq: htcGridConfig.sqs_dlq,
  sqsQueue: htcGridConfig.sqs_queue,
  targetValue:htcGridConfig.htc_agent_target_value,
  taskConfig: htcGridConfig.task_queue_config,
  taskInputPassedViaExternalStorage: htcGridConfig.task_input_passed_via_external_storage,
  taskService: htcGridConfig.task_queue_service,
  taskTtlExpirationOffsetSec: htcGridConfig.task_ttl_expiration_offset_sec,
  taskTtlRefreshIntervalSec: htcGridConfig.task_ttl_refresh_interval_sec,
  terminationGracePeriodSeconds: htcGridConfig.graceful_termination_delay,
  workProcStatusPullIntervalSec: htcGridConfig.work_proc_status_pull_interval_sec,
  env: env,
  cluster: clusterStack.eksCluster,
  apiKeySecret: schedulerStack.apiKeySecret,
  apiKey:schedulerStack.apiKey,
  apiGwKey: schedulerStack.apiGwKey,
  publicApiGwUrl: schedulerStack.publicApiGwUrl,
  privateApiGwUrl: schedulerStack.privateApiGwUrl,
  userpoolId: authStack.cognito_userpool.userPoolId,
  // Using `client` vs `user_data_client`, does this need to be changed?
  userpoolClientId: authStack.cognito_userpool_client.userPoolClientId,
  redisUrl: schedulerStack.redisUrl,
});

htcStack.addDependency(authStack);
htcStack.addDependency(schedulerStack);
