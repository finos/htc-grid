// Write up design/reference doc

import {Construct} from "constructs";
import * as cdk from "aws-cdk-lib";
import * as path from "path";
import * as lambda from "aws-cdk-lib/aws-lambda";
import * as eks from "aws-cdk-lib/aws-eks";
import * as iam from "aws-cdk-lib/aws-iam";
import * as cr from "aws-cdk-lib/custom-resources";
import * as assets from "aws-cdk-lib/aws-s3-assets";
import {KubectlLayer} from "aws-cdk-lib/lambda-layer-kubectl";
import {AwsCliLayer} from "aws-cdk-lib/lambda-layer-awscli";

export interface ClusterManagerPlusProps {
  readonly cluster: eks.ICluster;
}

export interface CreateHelmChartProps extends eks.HelmChartOptions {
  readonly assetChart?: assets.Asset;
  readonly assetValues?: assets.Asset[];
}

export interface ApplyProps {
  /**
   * @default false
   */
  readonly skipValidation?: boolean;
  /**
   * The manifest to apply.
   */
  readonly manifest?: Record<string, any>[];
  /**
   * @default false
   */
  readonly overwrite?: boolean;
  readonly assetManifest: assets.Asset;
}

interface IS3Asset {
  Bucket: string;
  ObjectKey: string;
}

export interface CustomKubectlProps {
  /**
   * @example
   * `kubectl {cmd} --kubeconfig {kubeconfig}`
   */
  readonly kubectlCreateCmd: string;
  readonly kubectlUpdateCmd?: string;
  readonly kubectlDeleteCmd?: string;
}

enum ResourceType {
  Helm = "Custom::ClusterManagerPlus-HelmChart",
  Apply = "Custom::ClusterManagerPlus-Apply",
  Custom = "Custom::ClusterManagerPlus-Custom",
}

export class ClusterManagerPlus extends Construct {
  readonly stack: cdk.Stack;
  readonly cluster: eks.ICluster;

  private codeResourcePath = path.join(__dirname, "./lambda");
  private handler: lambda.SingletonFunction;
  private provider: cr.Provider;
  private resourceCounter = 0;
  private readGranted = false;

  constructor(
    scope: Construct,
    id: string,
    props: ClusterManagerPlusProps
  ) {
    super(scope, id);

    this.stack = cdk.Stack.of(this);
    this.cluster = props.cluster;
    this.handler = this.createHandler();
    this.provider = this.createProvider();
  }

  private createHandler(): lambda.SingletonFunction {
    const memorySize = this.cluster.kubectlMemory
      ? this.cluster.kubectlMemory.toMebibytes()
      : 1024;
    let roleArn = "";
    if (this.cluster.kubectlRole !== undefined) {
      roleArn = this.cluster.kubectlRole.roleArn;
    }
    const handler = new lambda.SingletonFunction(this, "cmpKubectlHandler", {
      functionName: `${this.stack.stackName}-CdkEksClusterManagerPlus`,
      code: lambda.Code.fromAsset(this.codeResourcePath),
      runtime: lambda.Runtime.PYTHON_3_7,
      handler: "index.handler",
      timeout: cdk.Duration.minutes(15),
      uuid: "aws-cdk-lib/aws-eks.ClusterManagerPlus",
      description: "onEvent handler for EKS CMP kubectl resource provider",
      memorySize: memorySize,
      environment: {
        ClusterName: this.cluster.clusterName,
        RoleArn: roleArn,
      },
      layers: [
        new KubectlLayer(this, "kubectlLayer"),
        new AwsCliLayer(this, "awsCliLayer"),
      ],
      vpc: this.cluster.kubectlPrivateSubnets ? this.cluster.vpc : undefined,
      securityGroups: this.cluster.kubectlSecurityGroup
        ? [this.cluster.kubectlSecurityGroup]
        : undefined,
      vpcSubnets: this.cluster.kubectlPrivateSubnets
        ? {subnets: this.cluster.kubectlPrivateSubnets}
        : undefined,
    });

    if (handler.role !== undefined) {
      handler.role.addToPrincipalPolicy(
        new iam.PolicyStatement({
          actions: ["eks:DescribeCluster"],
          resources: [this.cluster.clusterArn],
        })
      );
      if (this.cluster.kubectlRole !== undefined) {
        this.cluster.kubectlRole.grant(handler.role, "sts:AssumeRole");
      }
    }
    return handler;
  }

  private createProvider(): cr.Provider {
    const provider = new cr.Provider(this, "CmpProvider", {
      onEventHandler: this.handler,
      vpc: this.cluster.kubectlPrivateSubnets ? this.cluster.vpc : undefined,
      securityGroups: this.cluster.kubectlSecurityGroup
        ? [this.cluster.kubectlSecurityGroup]
        : undefined,
      vpcSubnets: this.cluster.kubectlPrivateSubnets
        ? {subnets: this.cluster.kubectlPrivateSubnets}
        : undefined,
    });
    return provider;
  }

  public createHelmChart(
    stack: cdk.Stack,
    props: CreateHelmChartProps
  ): cdk.CustomResource {
    const timeout = props.timeout?.toSeconds();
    if (timeout && timeout > 900) {
      throw new Error("Helm chart timeout cannot be higher than 15 minutes.");
    }

    // default not to wait
    const wait = props.wait ?? false;
    // default to create new namespace
    const createNamespace = props.createNamespace ?? undefined;

    const repo = props.repository ?? undefined;
    const chart = props.chart;
    // if repository or chart are a url, not applying a local helm chart
    const localChart = this.isUrl(repo) || this.isUrl(chart) ? false : true;
    const assetChart = props.assetChart
      ? this.getAsset(props.assetChart)
      : undefined;
    const assetValues = props.assetValues
      ? this.getAsset(props.assetValues)
      : undefined;
    this.resourceCounter++;
    return new cdk.CustomResource(stack, `CmpResource${this.resourceCounter}`, {
      serviceToken: this.provider.serviceToken,
      resourceType: ResourceType.Helm,
      properties: {
        // cdk default properties...
        Release:
          props.release ?? cdk.Names.uniqueId(this).slice(-53).toLowerCase(), // Helm has a 53 character limit for the name
        Chart: chart,
        Version: props.version,
        Wait: wait || undefined, // props are stringified so we encode “false” as undefined
        Timeout: timeout ? `${timeout.toString()}s` : undefined, // Helm v3 expects duration instead of integer
        Values: props.values ? stack.toJsonString(props.values) : undefined,
        Namespace: props.namespace ?? "default",
        Repository: repo,
        CreateNamespace: createNamespace,
        // CMP properties...
        LocalChart: localChart,
        S3Chart: assetChart,
        S3Values: assetValues,
      },
    });
  }

  private isUrl(item: string | undefined): boolean {
    if (item?.includes("https") || item?.includes(".com")) {
      return true;
    }
    return false;
  }

  private getAsset(
    assetValues: assets.Asset[] | assets.Asset
  ): IS3Asset[] | IS3Asset {
    if (Array.isArray(assetValues)) {
      const s3AssetValues: IS3Asset[] = [];
      assetValues.forEach((asset) => {
        s3AssetValues.push({
          Bucket: asset.s3BucketName,
          ObjectKey: asset.s3ObjectKey,
        });
        this.grantAssetAccess(asset);
      });
      return s3AssetValues;
    } else {
      this.grantAssetAccess(assetValues);
      return {
        Bucket: assetValues.s3BucketName,
        ObjectKey: assetValues.s3ObjectKey,
      };
    }
  }

  private grantAssetAccess(assetResource: assets.Asset) {
    if (!this.readGranted && this.handler.role !== undefined) {
      assetResource.grantRead(this.handler.role);
      this.readGranted = true;
    }
    return;
  }

  public applyManifest(
    stack: cdk.Stack,
    props: ApplyProps
  ): cdk.CustomResource {
    const manifestJson = props.manifest
      ? stack.toJsonString(props.manifest)
      : undefined;
    this.resourceCounter++;
    return new cdk.CustomResource(stack, `CmpResource${this.resourceCounter}`, {
      serviceToken: this.provider.serviceToken,
      resourceType: ResourceType.Apply,
      properties: {
        ManifestAsset: this.getAsset(props.assetManifest),
        Manifest: manifestJson,
        Overwrite: props.overwrite,
        SkipValidation: props.skipValidation,
      },
    });
  }

  public customKubectl(
    stack: cdk.Stack,
    props: CustomKubectlProps
  ): cdk.CustomResource {
    this.resourceCounter++;
    return new cdk.CustomResource(stack, `CmpResource${this.resourceCounter}`, {
      serviceToken: this.provider.serviceToken,
      resourceType: ResourceType.Custom,
      properties: {
        CreateCommand: props.kubectlCreateCmd,
        UpdateCommand: props.kubectlUpdateCmd,
        DeleteCommand: props.kubectlDeleteCmd,
      },
    });
  }
}
