// Resources Stack

import { Construct } from "constructs";
import * as cdk from "aws-cdk-lib"
import * as eks from "aws-cdk-lib/aws-eks";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as iam from "aws-cdk-lib/aws-iam";
import * as cr from "aws-cdk-lib/custom-resources";
import {IWorkerInfo, IInputRole, IWorkerGroup} from "../shared/cluster-interfaces";
import { EksClusterHelperStack } from "./eks_cluster_help";

interface EksClusterStackProps extends cdk.StackProps {
  vpc: ec2.IVpc;
  vpcDefaultSg: ec2.ISecurityGroup;
  clusterName: string;
  kubernetesVersion: string;
  inputRoles: IInputRole[];
  enablePrivateSubnet: string ;
  eksWorkerGroups: IWorkerGroup[];
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

    var k8sVersion = props.kubernetesVersion;
    var clusterName = props.clusterName;

    // Need to transform user configured bool into proper eks.EndpointAccess class value
    var endpointAccess = Boolean(props.enablePrivateSubnet)
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
      endpointAccess: endpointAccess,
      vpcSubnets: [{ subnetType: ec2.SubnetType.PRIVATE }],
      vpc: vpc,
      mastersRole: masterRole,
    });
    cdk.Tags.of(cluster).add("Environment", "training");
    cdk.Tags.of(cluster).add("GithubRepo", "cdk-aws-eks"); // terraform-aws-eks
    cdk.Tags.of(cluster).add("GithubOrg", "cdk-aws-modules"); // terraform-aws-modules
    cdk.Tags.of(cluster).add("Application", "htc-grid-solution");

    this.enableClusterLogging(cluster);
    this.mapInputRole(cluster,props.inputRoles);
    const eks_helper = new EksClusterHelperStack(this, "eks-helper-stack", {
      cluster: cluster,
      vpc: vpc,
      vpc_default_sg: vpcDefaultSg,
      eksWorkerGroups: props.eksWorkerGroups
    });
    this.eksCluster = cluster;
    this.workerInfo = eks_helper.worker_info;
  }
  private mapInputRole(cluster: eks.Cluster, inputRoles: IInputRole[]) {
    inputRoles.forEach((inputRole: IInputRole, index: number) => {
      console.log(inputRole)
      let role = iam.Role.fromRoleArn(
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
