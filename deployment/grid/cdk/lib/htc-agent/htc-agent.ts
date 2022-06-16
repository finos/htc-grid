// Copyright 2022 Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


import { Construct } from "constructs";
import * as cdk from "aws-cdk-lib";
import * as path from "path";
import * as asset from "aws-cdk-lib/aws-s3-assets";
import * as eks from "aws-cdk-lib/aws-eks";
import * as ssm from "aws-cdk-lib/aws-ssm";
import { ClusterManagerPlus } from "../shared/cluster-manager-plus/cluster-manager-plus";
import {IAgentDeploymentConfig} from "../shared/cluster-interfaces";
import * as secretsmanager from "aws-cdk-lib/aws-secretsmanager";
import * as iam from "aws-cdk-lib/aws-iam";
import { RetentionDays } from "aws-cdk-lib/aws-logs";
import {
  AwsCustomResource,
  AwsCustomResourcePolicy,
  AwsSdkCall,
  PhysicalResourceId,
} from "aws-cdk-lib/custom-resources";
import { IApiKey } from "aws-cdk-lib/aws-apigateway";
interface HtcAgentStackProps extends cdk.StackProps {
  readonly cluster: eks.ICluster;
  readonly apiKeySecret: secretsmanager.ISecret;
  readonly apiKey: IApiKey;
  readonly apiGwKey: string;
  readonly publicApiGwUrl: string;
  readonly privateApiGwUrl: string;
  readonly userpoolId: string;
  readonly userpoolClientId: string;
  readonly redisUrl: string;
  readonly projectName : string ;
  readonly s3BucketName : string; //=.toLowerCase();
  readonly ddbTableName : string;
  readonly ddbService : string;
  readonly ddbConfig : string;
  readonly ddbDefaultRead: number;
  readonly ddbDefaultWrite: number;
  readonly taskService :string ;
  readonly taskConfig : string;
  readonly sqsQueue: string;
  readonly sqsDlq: string
  readonly emptyTaskQueueBackoffTimeoutSec: number;
  readonly workProcStatusPullIntervalSec: number ;
  readonly taskTtlExpirationOffsetSec: number;
  readonly taskTtlRefreshIntervalSec: number;
  readonly dynamodbResultsPullIntervalSec: number;
  readonly agentTaskVisibilityTimeoutSec: number;
  readonly metricsAreEnabled: string ;
  readonly metricsSubmitTasksLambdaConnectionString: string
  readonly metricsCancelTasksLambdaConnectionString: string;
  readonly metricsGetResultsLambdaConnectionString: string;
  readonly metricsTtlCheckerLambdaConnectionString: string;
  readonly metricsPreAgentTasksLambdaConnectionString: string;
  readonly metricsPostAgentTasksLambdaConnectionString: string;
  readonly errorLogGroup: string;
  readonly errorLoggingStream: string;
  readonly taskInputPassedViaExternalStorage: number ;
  readonly gridStorageService:string ;
  readonly lambdaNameSubmitTasks:string ;
  readonly lambdaNameCancelTasks: string;
  readonly lambdaNameGetResults: string;
  readonly lambdaNameTtlChecker: string;
  readonly htcPathLogs: string;
  readonly agentUseCongestionControl: string;
  readonly enableXRay: string;
  readonly deploymentAgentName: string;
  readonly deploymentNamespace: string;
  readonly minReplicas: number;
  readonly maxReplicas: number;
  readonly targetValue: number;
  readonly terminationGracePeriodSeconds: number;
  readonly agentDeploymentConfig :IAgentDeploymentConfig ;


}

export class HtcAgentStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: HtcAgentStackProps) {
    super(scope, id, props);

    const cluster = props.cluster;

    const clusterManager = new ClusterManagerPlus(
      this,
      "HtcAgentClusterManager",
      {
        cluster: cluster,
      }
    );

    const influxdbAddress = new eks.KubernetesObjectValue(
      this,
      "InfluxdbAddress",
      {
        cluster: cluster,
        objectType: "service",
        objectName: "influxdb",
        objectNamespace: "influxdb",
        jsonPath: ".status.loadBalancer.ingress[0].hostname",
        timeout: cdk.Duration.minutes(1),
      }
    ).value;

    const apiKey: AwsSdkCall = {
      service: "APIGateway",
      action: "getApiKey",
      parameters: {
        apiKey: props.apiKey.keyId,
        includeValue: true,
      },
      physicalResourceId: PhysicalResourceId.of(`APIKey:${props.apiKey.keyId}`),
    };

    const apiKeyCr = new AwsCustomResource(this, "api-key-cr", {
      policy: AwsCustomResourcePolicy.fromStatements([
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          resources: [props.apiKey.keyArn],
          actions: ["apigateway:GET"],
        }),
      ]),
      logRetention: RetentionDays.ONE_DAY,
      onCreate: apiKey,
      onUpdate: apiKey,
    });

    apiKeyCr.node.addDependency(props.apiKey);
    const apikeyValue = apiKeyCr.getResponseField("value");

    const agentConfigData = {
      region: this.region,
      sqs_endpoint: `https://sqs.${this.region}.amazonaws.com`,
      sqs_queue: props.sqsQueue ,
      sqs_dlq: props.sqsDlq ,
      redis_url: props.redisUrl,
      cluster_name: cluster.clusterName,
      ddb_state_table: props.ddbTableName ,
      empty_task_queue_backoff_timeout_sec: props.emptyTaskQueueBackoffTimeoutSec,
      work_proc_status_pull_interval_sec: props.workProcStatusPullIntervalSec,
      task_ttl_expiration_offset_sec: props.taskTtlExpirationOffsetSec,
      task_ttl_refresh_interval_sec: props.taskTtlRefreshIntervalSec,
      dynamodb_results_pull_interval_sec: props.dynamodbResultsPullIntervalSec,
      agent_task_visibility_timeout_sec: props.agentTaskVisibilityTimeoutSec,
      task_input_passed_via_external_storage: props.taskInputPassedViaExternalStorage,
      lambda_name_ttl_checker: props.lambdaNameTtlChecker,
      lambda_name_submit_tasks: props.lambdaNameSubmitTasks,
      lambda_name_get_results: props.lambdaNameGetResults,
      lambda_name_cancel_tasks: props.lambdaNameCancelTasks,
      s3_bucket:props.s3BucketName,
      grid_storage_service: props.gridStorageService ,
      task_queue_service: props.taskService,
      task_queue_config: props.taskConfig ,
      tasks_queue_name: `${props.sqsQueue}__0`,
      state_table_service: props.ddbService,
      state_table_config: props.ddbConfig,
      htc_path_logs: props.htcPathLogs,
      error_log_group: props.errorLogGroup,
      error_logging_stream: props.errorLoggingStream,
      metrics_are_enabled: props.metricsAreEnabled,
      metrics_grafana_private_ip: influxdbAddress,
      metrics_submit_tasks_lambda_connection_string: props.metricsSubmitTasksLambdaConnectionString,
      metrics_cancel_tasks_lambda_connection_string: props.metricsCancelTasksLambdaConnectionString,
      metrics_pre_agent_connection_string: props.metricsPreAgentTasksLambdaConnectionString,
      metrics_post_agent_connection_string: props.metricsPostAgentTasksLambdaConnectionString,
      metrics_get_results_lambda_connection_string: props.metricsGetResultsLambdaConnectionString,
      metrics_ttl_checker_lambda_connection_string: props.metricsTtlCheckerLambdaConnectionString,
      agent_use_congestion_control: props.agentUseCongestionControl,
      user_pool_id: props.userpoolId,
      cognito_userpool_client_id: props.userpoolClientId,
      public_api_gateway_url: props.publicApiGwUrl,
      private_api_gateway_url: props.privateApiGwUrl,
      api_gateway_key: apikeyValue,
      enable_xray: props.enableXRay

    };
    new ssm.StringParameter(this,"GridConfiguration",{
      parameterName : `/${props.projectName}/grid/config`,
      stringValue: this.toJsonString(agentConfigData),
      description: "Configuration of the grid with runtime parameters"
    })
    const agentConfigMap = {
      apiVersion: "v1",
      kind: "ConfigMap",
      metadata: {
        namespace: "default",
        name: "agent-configmap",
      },
      data: {
        "Agent_config.tfvars.json": this.toJsonString(agentConfigData),
      },
    };

    new eks.KubernetesManifest(this, "HtcAgentManifest", {
      cluster: cluster,
      manifest: [agentConfigMap],
    });

    const lambdaHandler = (props.agentDeploymentConfig.lambda_container.lambda_handler_file_name == "" ) ? `${props.agentDeploymentConfig.lambda_container.lambda_handler_file_name}.${props.agentDeploymentConfig.lambda_container.lambda_handler_function_name}` : props.agentDeploymentConfig.lambda_container.lambda_handler_file_name;


    clusterManager.createHelmChart(this, {
      chart: "htc-agent",
      release: "htc-agent",
      namespace: props.deploymentNamespace,
      assetChart: new asset.Asset(this, "HtcAgentChartAsset", {
        path: path.join(__dirname, "../../../charts/agent-htc-lambda"),
      }),
      values: {
        fullnameOverride:  props.deploymentAgentName ,
        terminationGracePeriodSeconds: props.terminationGracePeriodSeconds,
        storage: props.agentDeploymentConfig.get_layer.lambda_layer_type ,
        lambda: {
          s3Location: props.agentDeploymentConfig.lambda_container.location,
          functionName: props.agentDeploymentConfig.lambda_container.function_name,
          handler: lambdaHandler,
          region: this.region,
        },

        // Agent Section
        imageAgent: {
          repository: props.agentDeploymentConfig.agent_container.image,
          version:  props.agentDeploymentConfig.agent_container.tag,
          pullPolicy:  props.agentDeploymentConfig.agent_container.pullPolicy,
        },
        resourcesAgent: {
          requests: {
            cpu: `${props.agentDeploymentConfig.agent_container.minCPU}m`, // include m in variable
            memory: `${props.agentDeploymentConfig.agent_container.minMemory}Mi`, //include Mi in variable
          },
          limits: {
            cpu: `${props.agentDeploymentConfig.agent_container.maxCPU}m`, // include m in variable
            memory: `${props.agentDeploymentConfig.agent_container.maxMemory}Mi`, //include Mi in variable
          },
        },

        // Test Section
        imageTestAgent: {
          repository: props.agentDeploymentConfig.test.image,
          version: props.agentDeploymentConfig.test.tag,
          pullPolicy: props.agentDeploymentConfig.test.pullPolicy,
        },

        // Lambda Section
        imageLambdaServer: {
          repository: props.agentDeploymentConfig.lambda_container.image,
          version: props.agentDeploymentConfig.lambda_container.runtime,
          pullPolicy: props.agentDeploymentConfig.lambda_container.pullPolicy,
        },
        resourcesLambdaServer: {
          limits: {
            cpu: `${props.agentDeploymentConfig.lambda_container.maxCPU}m`,
            memory: `${props.agentDeploymentConfig.lambda_container.maxMemory}Mi`,
          },
          requests: {
            cpu: `${props.agentDeploymentConfig.lambda_container.minCPU}m`,
            memory: `${props.agentDeploymentConfig.lambda_container.minMemory}Mi`
          },
        },

        // Get-Layer Section
        imageGetLayer: {
          repository:  props.agentDeploymentConfig.get_layer.image,
          version:  props.agentDeploymentConfig.get_layer.tag,
          pullPolicy: props.agentDeploymentConfig.get_layer.pullPolicy,
        },
      },
    });
  }
}
