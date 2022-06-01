// Namespace: prometheus
import * as path from "path";
import { Construct } from "constructs";
import * as cdk from "aws-cdk-lib";
import * as eks from "aws-cdk-lib/aws-eks";
import * as asset from "aws-cdk-lib/aws-s3-assets";
import { ClusterManagerPlus } from "../shared/cluster-manager-plus/cluster-manager-plus";

interface PrometheusProps extends cdk.NestedStackProps {
  readonly clusterManager: ClusterManagerPlus;
  readonly nodeExporterTag: string;
  readonly prometheusTag: string;
  readonly alertManagerTag: string;
  readonly pushGatewayTag: string;
  readonly kubeStateMetricsTag: string;
  readonly configMapReloadTag: string;

}

// interface IPrometheusConfig {
//     node_exporter_tag: string,
//     server_tag: string,
//     alertmanager_tag: string,
//     kube_state_metrics_tag: string,
//     pushgateway_tag: string,
//     configmap_reload_tag: string
// }

export class PrometheusStack extends cdk.NestedStack {
  constructor(scope: Construct, id: string, props: PrometheusProps) {
    super(scope, id, props);

    const clusterManager = props.clusterManager;

    const prometheus_namespace_manifest = {
      apiVersion: "v1",
      kind: "Namespace",
      metadata: {
        name: "prometheus",
        annotations: {
          name: "prometheus",
        },
      },
    };

    const prometheus_namespace = new eks.KubernetesManifest(
      this,
      "prometheus-namespace",
      {
        cluster: clusterManager.cluster,
        manifest: [prometheus_namespace_manifest],
      }
    );

    const prometheus = clusterManager.createHelmChart(this, {
      namespace: "prometheus",
      chart: "prometheus",
      repository: "https://prometheus-community.github.io/helm-charts",
      release: "prometheus",
      assetValues: [
        new asset.Asset(this, "HtcPrometheusValues", {
          path: path.join(__dirname, "./prometheus-conf.yaml"),
        }),
      ],
      values: {
        nodeExporter: {
          image: {
            repository: `${this.account}.dkr.ecr.${this.region}.amazonaws.com/node-exporter`,
            tag: props.nodeExporterTag,
          },
        },
        server: {
          image: {
            repository: `${this.account}.dkr.ecr.${this.region}.amazonaws.com/prometheus`,
            tag: props.prometheusTag,
          },
          persistentVolume: {
            enabled: "false",
          },
        },
        alertmanager: {
          persistentVolume: {
            enabled: "false",
          },
          image: {
            repository: `${this.account}.dkr.ecr.${this.region}.amazonaws.com/alertmanager`,
            tag: props.alertManagerTag,
          },
        },
        pushgateway: {
          persistentVolume: {
            enabled: "false",
          },
          image: {
            repository: `${this.account}.dkr.ecr.${this.region}.amazonaws.com/pushgateway`,
            tag: props.pushGatewayTag,
          },
        },
        "kube-state-metrics": {
          image: {
            repository: `${this.account}.dkr.ecr.${this.region}.amazonaws.com/kube-state-metrics`,
            tag: props.kubeStateMetricsTag,
          },
          resources: {
            limits: {
              memory: "6Gi",
              cpu: "3000m",
            },
            requests: {
              memory: "1Gi",
              cpu: "500m",
            },
          },
        },
        configmapReload: {
          prometheus: {
            image: {
              repository: `${this.account}.dkr.ecr.${this.region}.amazonaws.com/configmap-reload`,
              tag: props.configMapReloadTag,
            },
          },
          alertmanager: {
            image: {
              repository: `${this.account}.dkr.ecr.${this.region}.amazonaws.com/configmap-reload`,
              tag: props.configMapReloadTag,
            },
          },
        },
      },
    });

    prometheus.node.addDependency(prometheus_namespace);
  }
}
