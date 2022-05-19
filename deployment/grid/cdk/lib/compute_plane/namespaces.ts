// eks resource creation
import { Construct } from "constructs";
import * as cdk from "aws-cdk-lib"
import * as eks from "aws-cdk-lib/aws-eks";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import { ClusterManagerPlus } from "../shared/cluster-manager-plus/cluster-manager-plus";
import { GrafanaStack } from "./grafana";
import { KubeSystemStack } from "./kube-system";
import { InfluxdbStack } from "./influxdb";
import { PrometheusStack } from "./prometheus";
import { CustomMetricsStack } from "./custom-metrics";
import { ContainerInsightStack } from "./amazon-cloudwatch";

interface NamespacesProps extends cdk.StackProps {
  readonly vpc: ec2.IVpc;
  readonly vpc_default_sg: ec2.ISecurityGroup;
  readonly cluster: eks.ICluster;

  // kube-system related properties
  readonly awsNodeTerminationHandlerTag: string;
  readonly clusterAutoscalerTag: string;
  readonly xRayDaemonTag: string;


  //ContainerInsight related properties
  readonly cwAgentTag: string;
  readonly awsForFluentBitTag: string

  //InfluxDB related properties
  readonly influxDbTag: string ;

  // prometheus related properties
  readonly nodeExporterTag: string;
  readonly prometheusTag: string;
  readonly alertManagerTag: string;
  readonly pushGatewayTag: string;
  readonly kubeStateMetricsTag: string;
  readonly configMapReloadTag: string;

  // grafana related properties
  readonly grafanaAdminPassword: string;
  readonly busyboxTag: string;
  readonly grafanaTag: string;
  readonly curlTag: string;
  readonly k8sSideCarTag: string;

  //cutom metrics properties
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

export class NamespacesStack extends cdk.Stack {
  public clusterManager: ClusterManagerPlus;
  public nlbInfluxDb : string;

  constructor(scope: Construct, id: string, props: NamespacesProps) {
    super(scope, id, props);
    const cluster = props.cluster;

    // Manager that will be used to add all helm charts
    this.clusterManager = new ClusterManagerPlus(this, "CustomClusterManager", {
      cluster: cluster,
    });
    // depends on eks helper stack
    const kubeSystemStack = new KubeSystemStack(this, "kubeSystem", {
      awsNodeTerminationHandlerTag: props.awsNodeTerminationHandlerTag,
      clusterAutoscalerTag: props.clusterAutoscalerTag,
      xRayDaemonTag: props.xRayDaemonTag,
      clusterManager: this.clusterManager
    });
    const containerInsightsStack = new ContainerInsightStack(
      this,
      "containerInsights",
      {
        clusterManager: this.clusterManager,
        awsForFluentBitTag: props.awsForFluentBitTag,
        cwaTag: props.cwAgentTag
      }
    );
    containerInsightsStack.addDependency(kubeSystemStack);
    // no dependencies
    const influxDb  = new InfluxdbStack(this, "influxdb", {
      clusterManager: this.clusterManager,
      influxDbTag: props.influxDbTag
    });
    this.nlbInfluxDb = influxDb.nlbInfluxDb ;
    // no dependencies
    new PrometheusStack(this, "prometheus", {
      alertManagerTag: props.alertManagerTag,
      configMapReloadTag: props.configMapReloadTag,
      kubeStateMetricsTag: props.kubeStateMetricsTag,
      nodeExporterTag: props.nodeExporterTag,
      prometheusTag: props.prometheusTag,
      pushGatewayTag: props.pushGatewayTag,
      clusterManager: this.clusterManager
    });
    // depends on ALB created in kubeSystemStack
    const grafanaStack = new GrafanaStack(this, "grafana", {
      clusterManager: this.clusterManager,
      busyboxTag: props.busyboxTag,
      curlTag: props.curlTag,
      grafanaAdminPassword: props.grafanaAdminPassword,
      grafanaTag: props.grafanaTag,
      k8sSideCarTag: props.k8sSideCarTag

    });
    grafanaStack.addDependency(kubeSystemStack);
    // depends on ALB created in kubeSystemStack
    const customMetricsStack = new CustomMetricsStack(this, "customMetrics", {
      clusterManager: this.clusterManager,
      averagePeriod: props.averagePeriod,
      cwaTag: props.cwaTag,
      deploymentAgentName: props.deploymentAgentName,
      deploymentNamespace: props.deploymentNamespace,
      maxReplicas: props.maxReplicas,
      metricDimensionName: props.metricDimensionName,
      metricDimensionValue: props.metricDimensionValue,
      metricName: props.metricName,
      metricNamespace: props.metricNamespace,
      minReplicas: props.minReplicas,
      targetValue: props.targetValue
    });
    customMetricsStack.addDependency(kubeSystemStack);
  }
}
