// Namespace: kube-system
// alb_ingress_controller
// cluster_autoscaler
// xray
// coredns patch

import * as path from "path";
import { Construct } from "constructs";
import * as cdk from "aws-cdk-lib"
import * as eks from "aws-cdk-lib/aws-eks";
import * as fs from "fs";
import * as yaml from "js-yaml";
import * as asset from "aws-cdk-lib/aws-s3-assets";
import { ClusterManagerPlus } from "../shared/cluster-manager-plus/cluster-manager-plus";

interface KubeSystemProps extends cdk.NestedStackProps {
  readonly clusterManager: ClusterManagerPlus;
  readonly awsNodeTerminationHandlerTag: string;
  readonly clusterAutoscalerTag: string;
  readonly xRayDaemonTag: string;
}

export class KubeSystemStack extends cdk.NestedStack {
  constructor(scope: Construct, id: string, props: KubeSystemProps) {
    super(scope, id, props);

    const clusterManager = props.clusterManager;
    const NAMESPACE = "kube-system";

    const aws_node_termination_handler_version = props.awsNodeTerminationHandlerTag
    const cluster_autoscaler_version = props.clusterAutoscalerTag;
    const coredns_file = path.join(__dirname, "patch-toleration-selector.yaml");
    const coredns_patch_data = this.yamlToJson(coredns_file);

    // Move to eks stack?
    new eks.KubernetesPatch(this, "patch-coredns", {
      applyPatch: coredns_patch_data,
      cluster: clusterManager.cluster,
      resourceName: "deployment/coredns",
      resourceNamespace: NAMESPACE,
      restorePatch: coredns_patch_data, // ?
    });
    // this installed as part of cdk call adding autoScalingGroupCapacity, do we still need to add this?
    // https://docs.aws.amazon.com/cdk/api/latest/docs/aws-eks-readme.html#spot-instances
    // --- Node Termination Handler Helm Chart
    clusterManager.createHelmChart(this, {
      chart: "aws-node-termination-handler",
      assetChart: new asset.Asset(this, "HtcNodeTerminationHandlerChart", {
        path: path.join(
          __dirname,
          `../../../charts/aws-node-termination-handler/${aws_node_termination_handler_version}`
        ),
      }),
      namespace: NAMESPACE,
      release: "aws-node-termination-handler",
      values: {
        image: {
          tag: aws_node_termination_handler_version,
        },
      },
    });
    //--- ALB Ingress Controller ---
    clusterManager.createHelmChart(this, {
      chart: "alb-controller",
      assetChart: new asset.Asset(this, "HtcAlbIngressChart", {
        path: path.join(__dirname, "../../../charts/aws-load-balancer-controller"),
      }),
      namespace: NAMESPACE,
      release: "alb-controller",
      assetValues: [
        new asset.Asset(this, "HtcAlbIngressValues", {
          path: path.join(__dirname, "./alb-ingress-controller-conf.yaml"),
        }),
      ],
      values: {
        clusterName: clusterManager.cluster.clusterName, //variable
        image: {
          repository: `602401143452.dkr.ecr.${this.region}.amazonaws.com/amazon/aws-load-balancer-controller`,
        },
      },
    });
    const xray_daemonset = {
      apiVersion: "apps/v1",
      kind: "DaemonSet",
      metadata: {
        name: "xray-daemon",
        namespace: NAMESPACE,
      },
      spec: {
        selector: {
          matchLabels: {
            app: "xray-daemon",
          },
        },
        template: {
          metadata: {
            labels: {
              app: "xray-daemon",
            },
          },
          spec: {
            volumes: [
              {
                name: "config-volume",
                configMap: {
                  name: "xray-config",
                },
              },
            ],
            containers: [
              {
                name: "xray-daemon",
                image: `${this.account}.dkr.ecr.${this.region}.amazonaws.com/aws-xray-daemon:${props.xRayDaemonTag}`,
                command: [
                  "/xray",
                  "-c",
                  "/aws/xray/config.yaml",
                  "-l",
                  "dev",
                  "-t",
                  "0.0.0.0:2000",
                ],
                ports: [
                  {
                    name: "xray-ingest",
                    hostPort: 2000,
                    containerPort: 2000,
                    protocol: "UDP",
                  },
                  {
                    name: "xray-tcp",
                    hostPort: 2000,
                    containerPort: 2000,
                    protocol: "TCP",
                  },
                ],
                resources: {
                  limits: {
                    cpu: "512m",
                    memory: "64Mi",
                  },
                  requests: {
                    memory: "32Mi",
                    cpu: "256m",
                  },
                },
                volumeMounts: [
                  {
                    name: "config-volume",
                    readOnly: true,
                    mountPath: "/aws/xray",
                  },
                ],
              },
            ],
          },
        },
        updateStrategy: {
          type: "RollingUpdate",
        },
      },
    };
    const xray_config_map = {
      apiVersion: "v1",
      kind: "ConfigMap",
      metadata: {
        name: "xray-config",
        namespace: NAMESPACE,
      },
      data: {
        "config.yaml":
          'TotalBufferSizeMB: 24\nSocket:\n  UDPAddress: "0.0.0.0:2000"\n  TCPAddress: "0.0.0.0:2000"\nVersion: 2',
      },
    };
    const xray_service = {
      apiVersion: "v1",
      kind: "Service",
      metadata: {
        name: "xray-service",
        namespace: NAMESPACE,
      },
      spec: {
        // cluster_ip: "None", // is this needed/how is it supposed to be passed in?
        selector: {
          app: "xray-daemon",
        },
        ports: [
          {
            name: "xray-ingest",
            protocol: "UDP",
            port: 2000,
          },
          {
            name: "xray-tcp",
            protocol: "TCP",
            port: 2000,
          },
        ],
      },
    };

    new eks.KubernetesManifest(this, "xray_daemonset", {
      cluster: clusterManager.cluster,
      manifest: [xray_daemonset],
    });
    new eks.KubernetesManifest(this, "xray_config_map", {
      cluster: clusterManager.cluster,
      manifest: [xray_config_map],
    });
    new eks.KubernetesManifest(this, "xray_service_daemonset", {
      cluster: clusterManager.cluster,
      manifest: [xray_service],
    });
    // --- Cluster Autoscaler
    clusterManager.createHelmChart(this, {
      chart: "cluster-autoscaler",
      namespace: NAMESPACE,
      repository: "https://kubernetes.github.io/autoscaler",
      release: "cluster-autoscaler",
      assetValues: [
        new asset.Asset(this, "HtcClusterAutoscalerValues", {
          path: path.join(__dirname, "./ca_placement_conf.yaml"),
        }),
      ],
      values: {
        autoDiscovery: {
          clusterName: clusterManager.cluster.clusterName,
        },
        awsRegion: this.region,
        image: {
          repository: `${this.account}.dkr.ecr.${this.region}.amazonaws.com/cluster-autoscaler`,
          tag: cluster_autoscaler_version,
        },
      },
    });

  }
  // helper function to convert yaml file to json
  private yamlToJson(file_path: string) {
    const yaml_data = yaml.load(
      fs.readFileSync(file_path, { encoding: "utf-8" })
    );
    // have to convert to json string before can turn into object
    const yaml_parsing = JSON.stringify(yaml_data, null, 2);
    return JSON.parse(yaml_parsing);
  }
}
