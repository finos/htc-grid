import * as path from "path";
import { Construct } from "constructs";
import * as cdk from "aws-cdk-lib"
import * as eks from "aws-cdk-lib/aws-eks";
import * as asset from "aws-cdk-lib/aws-s3-assets";
import { ClusterManagerPlus } from "../shared/cluster-manager-plus/cluster-manager-plus";

interface InfluxdbProps extends cdk.NestedStackProps {
  readonly clusterManager: ClusterManagerPlus;
  readonly influxDbTag: string ;
}

export class InfluxdbStack extends cdk.NestedStack {
  constructor(scope: Construct, id: string, props: InfluxdbProps) {
    super(scope, id, props);

    const clusterManager = props.clusterManager;

    const influxdb_namespace_manifest = {
      apiVersion: "v1",
      kind: "Namespace",
      metadata: {
        name: "influxdb",
        annotations: {
          name: "influxdb",
        },
      },
    };

    const influxdb_namespace = new eks.KubernetesManifest(
      this,
      "influxdb-namespace",
      {
        cluster: clusterManager.cluster,
        manifest: [influxdb_namespace_manifest],
      }
    );

    const influxdb = clusterManager.createHelmChart(this, {
      namespace: "influxdb",
      chart: "influxdb",
      repository: "https://helm.influxdata.com/",
      release: "influxdb",
      assetValues: [
        new asset.Asset(this, "HtcInfluxDb", {
          path: path.join(__dirname, "./influxdb-conf.yaml"),
        }),
      ],
      values: {
        persistence: {
          enabled: "false",
        },
        image: {
          repository: `${this.account}.dkr.ecr.${this.region}.amazonaws.com/influxdb`,
          tag: props.influxDbTag,
        },
        service: {
          type: "LoadBalancer",
          annotations: {
            "service.beta.kubernetes.io/aws-load-balancer-internal": "true",
            "service.beta.kubernetes.io/aws-load-balancer-type": "nlb",
          },
        },
      },
    });

    influxdb.node.addDependency(influxdb_namespace);
  }
}
