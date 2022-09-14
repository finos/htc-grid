// Copyright 2022 Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import { Construct } from "constructs";
import * as cdk from "aws-cdk-lib";
import * as asg from "aws-cdk-lib/aws-autoscaling";
import * as cr from "aws-cdk-lib/custom-resources";
import * as eks from "aws-cdk-lib/aws-eks";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as iam from "aws-cdk-lib/aws-iam";
import * as lambda from "aws-cdk-lib/aws-lambda";
import * as lambdaPy from "@aws-cdk/aws-lambda-python-alpha";
import * as events from "aws-cdk-lib/aws-events";
import { LambdaFunction } from "aws-cdk-lib/aws-events-targets";
import * as logs from "aws-cdk-lib/aws-logs";
import { IWorkerInfo } from "../shared/cluster-interfaces";
import * as path from "path";
import * as yaml from 'yaml'
import * as fs from 'fs'


interface LambdaDrainerScalingProps extends cdk.NestedStackProps {
  readonly  vpc: ec2.IVpc;
  readonly vpcDefaultSg: ec2.ISecurityGroup;
  readonly cluster: eks.ICluster;
  readonly workerInfo: IWorkerInfo[];
  readonly privateSubnetSelector: ec2.SubnetSelection;
  readonly drainerLambdaRole: iam.IRole;
  readonly gracefulTerminationDelay: number;
  readonly projectName: string;
  readonly ddbTableName : string;
  readonly taskService :string ;
  readonly taskConfig : string;
  readonly sqsQueue: string;
  readonly errorLogGroup: string;
  readonly errorLoggingStream: string;
  readonly lambdaNameScalingMetrics: string;
  readonly namespaceMetrics: string;
  readonly dimensionNameMetrics: string;
  readonly periodMetrics: string;
  readonly metricsName: string;
  readonly metricsEventRuleTime: string;
  readonly tasksQueueName: string;
}

export class LambdaDrainerScalingStack extends cdk.NestedStack {
  private vpc: ec2.IVpc;
  private vpcDefaultSg: ec2.ISecurityGroup;
  private cluster: eks.ICluster;
  private workerInfo: IWorkerInfo[];
  private privateSubnetSelector: ec2.SubnetSelection;
  private ddbTableName: string;
  private lambdaNameScalingMetrics: string;
  private namespaceMetrics: string;
  private dimensionNameMetrics: string;
  private periodMetrics: string;
  private metricsName: string;
  private metricsEventRuleTime: string;

  private taskService: string;
  private taskConfig: string;
  private sqsQueueName: string;
  private errorLogGroup: string;
  private errorLoggingStream: string;
  private tasksQueueName: string;
  private drainerLambdaRole: iam.IRole;
  private readyCheckProvider: cr.Provider;

  constructor(
    scope: Construct,
    id: string,
    props: LambdaDrainerScalingProps
  ) {
    super(scope, id, props);

    this.vpc = props.vpc;
    this.vpcDefaultSg = props.vpcDefaultSg;
    this.cluster = props.cluster;
    this.workerInfo = props.workerInfo;
    this.privateSubnetSelector = props.privateSubnetSelector;
    this.ddbTableName = props.ddbTableName;
    this.taskService=props.taskService;
    this.taskConfig=props.taskConfig;
    this.sqsQueueName=props.sqsQueue;
    this.privateSubnetSelector = props.privateSubnetSelector;
    this.errorLogGroup=props.errorLogGroup;
    this.errorLoggingStream=props.errorLoggingStream;
    this.lambdaNameScalingMetrics = props.lambdaNameScalingMetrics
    this.readyCheckProvider = this.createReadyCheckHandler();
    this.namespaceMetrics = props.namespaceMetrics;
    this.dimensionNameMetrics = props.dimensionNameMetrics;
    this.periodMetrics = props.periodMetrics;
    this.metricsName = props.metricsName;
    this.metricsEventRuleTime = props.metricsEventRuleTime;
    this.tasksQueueName = props.tasksQueueName;
    this.drainerLambdaRole = props.drainerLambdaRole;

    const drainerFunction =  this.createDrainerFunction(props.projectName);
    this.createAutoscalingEvent(drainerFunction,props.gracefulTerminationDelay);
    // this.addDrainerEksRole();
    const scaling_function = this.createScalingFunction(props.projectName);
    this.createScalingMetricsEvent(scaling_function);
  }
  private createReadyCheckHandler() {
    const handler = new lambda.Function(this, "CheckNodegroupStatus", {
      code: lambda.Code.fromAsset(
        path.join(__dirname, "../shared/nodegroup-checker")
      ),
      handler: "index.handler",
      runtime: lambda.Runtime.PYTHON_3_7,
      timeout: cdk.Duration.minutes(15),
    });
    handler.addToRolePolicy(
      new iam.PolicyStatement({
        actions: [
          "eks:DescribeNodegroup",
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
        ],
        resources: ["*"],
      })
    );
    return new cr.Provider(this, "NodegroupReadyProvider", {
      onEventHandler: handler,
    });
  }
  private createDrainerFunction(projectName: string): lambdaPy.PythonFunction {
    // Is this needed? CDK should create this, but may create extra permissions as well..
    const drainer_function = new lambdaPy.PythonFunction(
      this,
      "drainer-function",
      {
        entry: "../../../source/compute_plane/python/lambda/drainer",
        index: "handler.py",
        handler: "lambda_handler",
        functionName: `lambda_drainer-${projectName}`,
        runtime: lambda.Runtime.PYTHON_3_7,
        memorySize: 1024,
        timeout: cdk.Duration.seconds(900),
        role: this.drainerLambdaRole,
        vpc: this.vpc,
        vpcSubnets: this.privateSubnetSelector,
        securityGroups: [this.vpcDefaultSg],
        environment: {
          CLUSTER_NAME: this.cluster.clusterName,
        },
      }
    );



    const rBacYamlManifest = yaml.parseAllDocuments(fs.readFileSync('./lib/compute_plane/lambda_rbac.yaml', 'utf-8'))

    const rBacManifest = rBacYamlManifest.map(document => document.toJS())

    this.cluster.addManifest("DrainerRbac",...rBacManifest)
    cdk.Tags.of(drainer_function).add("service", "htc-aws");
    // Agent permissions
    // Believe CDK will already add this, but adding for terraform: cdk consistency (for now)

    return drainer_function;
  }

  private createAutoscalingEvent(lambda: lambdaPy.PythonFunction, gracefulTerminationDelay: number) {
    const timeout = gracefulTerminationDelay;
    const lambda_target = new LambdaFunction(lambda);
    this.workerInfo.forEach((worker, index) => {
      const autoScalingGroup = this.getAutoScalingGroupFromNodeGroup(
        worker.configs.name
      );
      autoScalingGroup.node.addDependency(worker.nodegroup);
      const asg_name = autoScalingGroup.autoScalingGroupName;
      // asg.addLifeCycleHook requires a target, have to use CfnLifecycleHook
      new asg.CfnLifecycleHook(this, `drainer_hook_${worker.configs.name}`, {
        autoScalingGroupName: asg_name,
        lifecycleTransition: asg.LifecycleTransition.INSTANCE_TERMINATING,
        defaultResult: asg.DefaultResult.ABANDON,
        heartbeatTimeout: timeout,
        lifecycleHookName: worker.configs.name,
      });
      new events.Rule(this, `event-lifecyclehook-${index}`, {
        ruleName: `event-lifecyclehook-${index}`,
        description: "Fires event when an EC2 instance is terminated",
        targets: [lambda_target],
        eventPattern: {
          detailType: ["EC2 Instance-terminate Lifecycle Action"],
          source: ["aws.autoscaling"],
          detail: {
            AutoScalingGroupName: [asg_name],
          },
        },
      });
    });
  }

  private createScalingFunction(projectName: string): lambdaPy.PythonFunction {
    const lambda_name = this.lambdaNameScalingMetrics;
    // Is this needed? CDK should create this, but may create extra permissions as well..
    const function_role = new iam.Role(this, "role_lambda_metrics", {
      roleName: `role_lambda_metrics-${projectName}`,
      assumedBy: new iam.ServicePrincipal("lambda.amazonaws.com"),
    });
    function_role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaVPCAccessExecutionRole")
    )
    new iam.Policy(this, "lambda_metrics_data_policy", {
      document: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            resources: ["*"],
            actions: [
              "dynamodb:*",
              "sqs:*",
              "cloudwatch:PutMetricData",
            ],
            effect: iam.Effect.ALLOW,
          }),
        ],
      }),
      policyName: "lambda_metrics_data_policy",
      roles: [function_role],
    });

    const lambdaBase = cdk.DockerImage.fromBuild("../../../", {
      file: "deployment/grid/cdk/lib/compute_plane/Dockerfile",
      buildArgs: {
        HTCGRID_ACCOUNT: cdk.Stack.of(this).account,
        HTCGRID_REGION:cdk.Stack.of(this).region
      }
    });

    const bundlingOptions = {
      image: lambdaBase,
        command: [
      "bash",
      "-c",
      `cp -r /asset-temp/* /asset-output && cp -au . /asset-output`,
    ],

    };

    const scaling_function = new lambda.Function(this, lambda_name, {
      code: lambda.Code.fromAsset("../../../source/compute_plane/python/lambda/scaling_metrics", {
        bundling: bundlingOptions,
      }),
      handler: "scaling_metrics.lambda_handler",
      functionName: lambda_name,
      runtime: lambda.Runtime.PYTHON_3_7,
      memorySize: 1024,
      timeout: cdk.Duration.seconds(60),
      role: function_role,
      vpc: this.vpc,
      vpcSubnets: this.privateSubnetSelector,
      securityGroups: [this.vpcDefaultSg],
      environment: {
        STATE_TABLE_CONFIG: this.ddbTableName,
        NAMESPACE: this.namespaceMetrics,
        DIMENSION_NAME: this.dimensionNameMetrics,
        DIMENSION_VALUE: this.cluster.clusterName,
        PERIOD: this.periodMetrics,
        METRICS_NAME: this.metricsName, // metrics_name in variables.tf, but metric_name in lambda_scaling.tf... need to investigate
        SQS_QUEUE_NAME: this.sqsQueueName,
        TASKS_QUEUE_NAME: this.tasksQueueName,
        REGION: this.region,
        TASK_QUEUE_SERVICE: this.taskService,
        TASK_QUEUE_CONFIG: this.taskConfig,
        ERROR_LOG_GROUP: this.errorLogGroup,
        ERROR_LOGGING_STREAM: this.errorLoggingStream,
      },
      logRetention: logs.RetentionDays.FIVE_DAYS,
    });
    cdk.Tags.of(scaling_function).add("service", "htc-aws");
    return scaling_function;
  }
  // Should add necessary permissions for rule to invoke
  private createScalingMetricsEvent(lambda: lambdaPy.PythonFunction) {
    const rule_name = "scaling_metrics_event_rule";
    const schedule_expression = this.metricsEventRuleTime
    const lambda_target = new LambdaFunction(lambda);
    new events.Rule(this, rule_name, {
      ruleName: rule_name,
      description: "Fires event rule to put metrics",
      schedule: events.Schedule.expression(schedule_expression),
      targets: [lambda_target],
    });
  }
  // No built in way to get ASG associated with nodegroup
  // The ASG is needed for drainer
  private getAutoScalingGroupFromNodeGroup(
    node: string
  ): asg.IAutoScalingGroup {
    const nodegroupReady = new cdk.CustomResource(
      this,
      `${node}NodegroupReady`,
      {
        serviceToken: this.readyCheckProvider.serviceToken,
        properties: {
          Cluster: this.cluster.clusterName,
          Nodegroup: node,
        },
      }
    );
    const describe_node_group = new cr.AwsCustomResource(
      this,
      `nodegroup_description_${node}`,
      {
        policy: cr.AwsCustomResourcePolicy.fromSdkCalls({
          resources: cr.AwsCustomResourcePolicy.ANY_RESOURCE,
        }),
        onCreate: {
          physicalResourceId: cr.PhysicalResourceId.fromResponse(
            "nodegroup.nodegroupName"
          ),
          service: "EKS",
          action: "describeNodegroup",
          region: this.region,
          parameters: {
            clusterName: this.cluster.clusterName,
            nodegroupName: node,
          },
        },
      }
    );
    // Nodegroup takes some time to become active, need to wait for nodegroup to be active before fetching ASG name
    describe_node_group.node.addDependency(nodegroupReady);
    const node_group_asg_name = describe_node_group?.getResponseField(
      "nodegroup.resources.autoScalingGroups.0.name"
    );
    return asg.AutoScalingGroup.fromAutoScalingGroupName(
      this,
      `nodegroup_asg_${node}`,
      node_group_asg_name!
    );
  }
}
