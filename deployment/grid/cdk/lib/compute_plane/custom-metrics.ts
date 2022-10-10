// Copyright 2022 Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


import * as path from "path";
import { Construct } from "constructs";
import * as cdk from "aws-cdk-lib";
import * as eks from "aws-cdk-lib/aws-eks";
import * as asset from "aws-cdk-lib/aws-s3-assets";
import { ClusterManagerPlus } from "../shared/cluster-manager-plus/cluster-manager-plus";

interface CustomMetricsStackProps extends cdk.NestedStackProps {
  readonly clusterManager: ClusterManagerPlus;
  readonly cwaTag: string;
  readonly metricName: string;
  readonly metricNamespace: string;
  readonly metricDimensionName: string;
  readonly metricDimensionValue: string;
  readonly averagePeriod: string;
  readonly deploymentAgentName: string;
  readonly deploymentNamespace: string;
  readonly minReplicas: number;
  readonly maxReplicas: number;
  readonly targetValue: number;

}

export class CustomMetricsStack extends cdk.NestedStack {
  constructor(
    scope: Construct,
    id: string,
    props: CustomMetricsStackProps
  ) {
    super(scope, id, props);

    const clusterManager = props.clusterManager;

    const namespace_manifest = {
      apiVersion: "v1",
      kind: "Namespace",
      metadata: {
        name: "custom-metrics",
        annotations: {
          name: "cw-adapter",
        },
      },
    };

    const cwnamespace = new eks.KubernetesManifest(
      this,
      "custom-metrics-namespace",
      {
        cluster: clusterManager.cluster,
        manifest: [namespace_manifest],
      }
    );

    const cwadapter = clusterManager.createHelmChart(this, {
      chart: "cloudwatch-adapter",
      assetChart: new asset.Asset(this, "HtcCWAdapterChart", {
        path: path.join(
          __dirname,
          `../../../charts/cloudwatch-adapter/${props.cwaTag}`
        ),
      }),
      namespace: "custom-metrics",
      release: "cloudwatch-adapter",
      values: {
        image: {
          tag: props.cwaTag, //var.CWA_VERSION, //variable
          repository: `${this.account}.dkr.ecr.${this.region}.amazonaws.com/k8s-cloudwatch-adapter`,
        },
        metric: {
          namespace: props.metricNamespace , //var.NAMESPACE_METRICS, //variable
          name: props.metricName,
          dimensionName:props.metricDimensionName,
          dimensionValue:props.metricDimensionValue,
          averagePeriod: props.averagePeriod
        },
        hpa: {
          deploymentName: props.deploymentAgentName ,
          deploymentNamespace: props.deploymentNamespace,
          minReplicas: props.minReplicas,
          maxReplicas: props.maxReplicas,
          targetValue: props.targetValue
        },
      },
    });

    // Enforce namespace creation before HelmChart is applied
    cwadapter.node.addDependency(cwnamespace);
  }
}
