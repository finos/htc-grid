// Copyright 2022 Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

// iam configurations needed for resources deployed into cluster

import { Construct } from "constructs";
import * as cdk from "aws-cdk-lib";
import * as iam from "aws-cdk-lib/aws-iam";
import * as alb from "./iam-policy-alb.json";

interface EksIamStackProps extends cdk.NestedStackProps {
  readonly worker_roles: iam.IRole[];
  readonly cluster_id: string;
}

export class EksIamStack extends cdk.NestedStack {
  private cluster_id: string;
  private worker_roles: iam.IRole[];
  private XRAY_ARN = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess";
  private SSM_ARN = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore";

  constructor(scope: Construct, id: string, props: EksIamStackProps) {
    super(scope, id, props);

    this.worker_roles = props.worker_roles;
    this.cluster_id = props.cluster_id;

    this.addFluentdPermissions();
    this.addAgentPermissions();
    this.addAutoScalingPermissions();
    this.addManagedPolicies();
    this.addAlbPolicy();
  }

  private addFluentdPermissions() {
    const permission_tag = "fluentd";
    const fluentd_document = new iam.PolicyDocument({
      statements: [
        new iam.PolicyStatement({
          resources: ["*"],
          actions: [
            "logs:DescribeLogGroups",
            "logs:DescribeLogStreams",
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents",
          ],
          effect: iam.Effect.ALLOW,
        }),
      ],
    });
    new iam.Policy(this, `${permission_tag}_policy`, {
      document: fluentd_document,
      policyName: `${permission_tag}-${this.cluster_id}`,
      roles: this.worker_roles,
    });
  }
  private addAgentPermissions() {
    const permission_tag = "eks-worker-assume-agent";
    const worker_assume_role_agent_permitions_document = new iam.PolicyDocument(
      {
        statements: [
          new iam.PolicyStatement({
            sid: "",
            resources: ["*"],
            actions: [
              "sqs:*",
              "dynamodb:*",
              "lambda:*",
              "logs:*",
              "s3:*",
              "firehose:*",
              "cloudwatch:PutMetricData",
              "cloudwatch:GetMetricData",
              "cloudwatch:GetMetricStatistics",
              "cloudwatch:ListMetrics",
              "route53:AssociateVPCWithHostedZone",
            ],
            effect: iam.Effect.ALLOW,
          }),
        ],
      }
    );

    new iam.Policy(this, `${permission_tag}_policy`, {
      document: worker_assume_role_agent_permitions_document,
      policyName: `${permission_tag}-${this.cluster_id}`,
      roles: this.worker_roles,
    });
  }
  private addAutoScalingPermissions() {
    const permission_tag = "eks-worker-autoscaling";
    const worker_autoscaling_document = new iam.PolicyDocument({
      statements: [
        new iam.PolicyStatement({
          sid: "eksWorkerAutoscalingAll",
          resources: ["*"],
          actions: [
            "autoscaling:DescribeAutoScalingGroups",
            "autoscaling:DescribeAutoScalingInstances",
            "autoscaling:DescribeLaunchConfigurations",
            "autoscaling:DescribeTags",
            "ec2:DescribeLaunchTemplateVersions",
          ],
          effect: iam.Effect.ALLOW,
        }),
        new iam.PolicyStatement({
          sid: "eksWorkerAutoscalingOwn",
          resources: ["*"],
          actions: [
            "autoscaling:SetDesiredCapacity",
            "autoscaling:TerminateInstanceInAutoScalingGroup",
            "autoscaling:UpdateAutoScalingGroup",
          ],
          effect: iam.Effect.ALLOW,
        }),
      ],
    });
    new iam.Policy(this, `${permission_tag}_policy`, {
      document: worker_autoscaling_document,
      policyName: `${permission_tag}-${this.cluster_id}`,
      roles: this.worker_roles,
    });
  }
  private addManagedPolicies() {
    const xray_document = iam.ManagedPolicy.fromManagedPolicyArn(
      this,
      "workers_xray",
      this.XRAY_ARN
    );
    const ssm_document = iam.ManagedPolicy.fromManagedPolicyArn(
      this,
      "workers_ssm",
      this.SSM_ARN
    );
    this.worker_roles.forEach((role: iam.IRole) => {
      role.addManagedPolicy(xray_document);
      role.addManagedPolicy(ssm_document);
    });
  }
  private addAlbPolicy() {
    const permission_tag = "alb";
    const alb_document = iam.PolicyDocument.fromJson(alb);
    new iam.Policy(this, `${permission_tag}_policy`, {
      document: alb_document,
      roles: this.worker_roles,
      policyName: "AWSLoadBalancerControllerIAMPolicy",
    });
  }
}
