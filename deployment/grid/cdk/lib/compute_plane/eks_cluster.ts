// Copyright 2022 Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


import { Construct } from "constructs";
import * as cdk from "aws-cdk-lib";
import * as eks from "aws-cdk-lib/aws-eks";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as iam from "aws-cdk-lib/aws-iam";
import * as cr from "aws-cdk-lib/custom-resources";
import {IWorkerInfo, IInputRole, IWorkerGroup} from "../shared/cluster-interfaces";
import { EksClusterHelperStack } from "./eks_cluster_help";

interface EksClusterStackProps extends cdk.StackProps {
  readonly vpc: ec2.IVpc;
  readonly vpcDefaultSg: ec2.ISecurityGroup;
  readonly clusterName: string;
  readonly kubernetesVersion: string;
  readonly inputRoles: IInputRole[];
  readonly enablePrivateSubnet: boolean ;
  readonly eksWorkerGroups: IWorkerGroup[];
  readonly gracefulTerminationDelay: number;
  readonly privateSubnetSelector: ec2.SubnetSelection;
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


export class EksClusterStack extends cdk.Stack {
  public readonly eksCluster: eks.ICluster;
  // Some attributes of cluster are not available on ICluster,
  // passing via custom interface
  public readonly workerInfo: IWorkerInfo[] = [];

  constructor(scope: Construct, id: string, props: EksClusterStackProps) {
    super(scope, id, props);

    const vpc = props.vpc;
    const vpcDefaultSg = props.vpcDefaultSg;

    const k8sVersion = props.kubernetesVersion;
    const clusterName = props.clusterName;

    // Need to transform user configured bool into proper eks.EndpointAccess class value
    const endpointAccess = props.enablePrivateSubnet
      ? eks.EndpointAccess.PUBLIC_AND_PRIVATE
      : eks.EndpointAccess.PUBLIC;

    const masterRole = new iam.Role(this, "EksMasterRole", {
      assumedBy: new iam.AccountRootPrincipal(),
    });

    // EKS Cluster
    const cluster = new eks.Cluster(this, "EKS Cluster", {
      version: eks.KubernetesVersion.of(k8sVersion),
      defaultCapacity: 0,
      clusterName: clusterName,
      vpcSubnets: [{
        subnetType: ec2.SubnetType.PUBLIC
      }, props.privateSubnetSelector],
      endpointAccess: endpointAccess,
      vpc: vpc,
      mastersRole: masterRole,
    });
    cdk.Tags.of(cluster).add("Environment", "training");
    cdk.Tags.of(cluster).add("GithubRepo", "cdk-aws-eks"); // terraform-aws-eks
    cdk.Tags.of(cluster).add("GithubOrg", "cdk-aws-modules"); // terraform-aws-modules
    cdk.Tags.of(cluster).add("Application", "htc-grid-solution");

    this.enableClusterLogging(cluster);
    this.mapInputRole(cluster,props.inputRoles);
    const lambdaDrainerRole = new iam.Role(this, "drainerLambdaRole", {
      roleName: `roleLambdaDrainer-${props.projectName}`,
      assumedBy: new iam.ServicePrincipal("lambda.amazonaws.com"),
      inlinePolicies: {
        AssumeRole: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              actions: ["sts:AssumeRole"],
              effect: iam.Effect.ALLOW,
              resources: ["*"],
            }),
          ],
        }),
      },
    });

    lambdaDrainerRole.addToPolicy(
      new iam.PolicyStatement({
        actions: [
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
        ],
        resources: ["*"],
      })
    );
    lambdaDrainerRole.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName(
        "service-role/AWSLambdaBasicExecutionRole"
      )
    );
    new iam.Policy(this, "lambda_drainer_policy", {
      document: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            resources: ["*"],
            actions: [
              "ec2:CreateNetworkInterface",
              "ec2:DeleteNetworkInterface",
              "ec2:DescribeNetworkInterfaces",
              "autoscaling:CompleteLifecycleAction",
              "ec2:DescribeInstances",
              "eks:DescribeCluster",
              "sts:GetCallerIdentity",
            ],
            effect: iam.Effect.ALLOW,
          }),
        ],
      }),
      policyName: "lambda-drainer-policy",
      roles: [lambdaDrainerRole],
    });
    cluster.awsAuth.addMastersRole(lambdaDrainerRole,"lambda")

    const eks_helper = new EksClusterHelperStack(this, "eks-helper-stack", {
      ddbTableName: props.ddbTableName,
      dimensionNameMetrics: props.dimensionNameMetrics,
      errorLogGroup: props.errorLogGroup,
      errorLoggingStream: props.errorLoggingStream,
      lambdaNameScalingMetrics: props.lambdaNameScalingMetrics,
      metricsEventRuleTime: props.metricsEventRuleTime,
      metricsName: props.metricsName,
      namespaceMetrics: props.namespaceMetrics,
      periodMetrics: props.periodMetrics,
      sqsQueue: props.sqsQueue,
      taskConfig: props.taskConfig,
      taskService: props.taskService,
      tasksQueueName: props.tasksQueueName,
      cluster: cluster,
      vpc: vpc,
      vpcDefaultSg: vpcDefaultSg,
      eksWorkerGroups: props.eksWorkerGroups,
      privateSubnetSelector: props.privateSubnetSelector,
      projectName: props.projectName,
      gracefulTerminationDelay: props.gracefulTerminationDelay,
      lambdaDrainerRole: lambdaDrainerRole
    });
    this.eksCluster = cluster;
    this.workerInfo = eks_helper.workerInfo;
  }
  private mapInputRole(cluster: eks.Cluster, inputRoles: IInputRole[]) {
    inputRoles.forEach((inputRole: IInputRole, index: number) => {
      console.log(inputRole);
      const role = iam.Role.fromRoleArn(
        this,
        `InputRole${index + 1}`,
        inputRole.rolearn
      );
      cluster.awsAuth.addRoleMapping(role, {
        groups: inputRole.groups,
        // username: inputRole.username
      });
    });
  }

  private enableClusterLogging(cluster: eks.Cluster) {
    // Need to enable log types ["api","audit","authenticator","controllerManager","scheduler"]
    // Per https://github.com/aws/aws-cdk/issues/4159#issuecomment-855625700, CustomResource needed to add logging atm
    new cr.AwsCustomResource(this, "ClusterLogsEnabler", {
      policy: cr.AwsCustomResourcePolicy.fromSdkCalls({
        resources: [`${cluster.clusterArn}/update-config`],
      }),
      onCreate: {
        physicalResourceId: { id: `${cluster.clusterArn}/LogsEnabler` },
        service: "EKS",
        action: "updateClusterConfig",
        region: this.region,
        parameters: {
          name: cluster.clusterName,
          logging: {
            clusterLogging: [
              {
                enabled: true,
                types: [
                  "api",
                  "audit",
                  "authenticator",
                  "controllerManager",
                  "scheduler",
                ],
              },
            ],
          },
        },
      },
      onDelete: {
        physicalResourceId: { id: `${cluster.clusterArn}/LogsEnabler` },
        service: "EKS",
        action: "updateClusterConfig",
        region: this.region,
        parameters: {
          name: cluster.clusterName,
          logging: {
            clusterLogging: [
              {
                enabled: false,
                types: [
                  "api",
                  "audit",
                  "authenticator",
                  "controllerManager",
                  "scheduler",
                ],
              },
            ],
          },
        },
      },
    });
  }
}
