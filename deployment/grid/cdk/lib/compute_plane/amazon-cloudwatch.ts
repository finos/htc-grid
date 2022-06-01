import { Construct } from "constructs";
import * as cdk from "aws-cdk-lib";
import * as eks from "aws-cdk-lib/aws-eks";
// import * as iam from "@aws-cdk/aws-iam";
import { ClusterManagerPlus } from "../shared/cluster-manager-plus/cluster-manager-plus";

interface ContainerInsightProps extends cdk.NestedStackProps {
  readonly clusterManager: ClusterManagerPlus;
  readonly cwaTag: string;
  readonly awsForFluentBitTag: string
}

export class ContainerInsightStack extends cdk.NestedStack {
  private NAMESPACE = "amazon-cloudwatch";
  private clusterManager: ClusterManagerPlus;

  private cloudWatchNamespace: eks.KubernetesManifest;

  constructor(scope: Construct, id: string, props: ContainerInsightProps) {
    super(scope, id, props);

    this.clusterManager = props.clusterManager;

    this.cloudWatchNamespace = this.createNamespace();
    this.createCloudWatchAgent(props.cwaTag);
    this.createFluentBit(props.awsForFluentBitTag);
  }

  private createNamespace(): eks.KubernetesManifest {
    return new eks.KubernetesManifest(this, "customMetricsNamespace", {
      cluster: this.clusterManager.cluster,
      manifest: [
        {
          apiVersion: "v1",
          kind: "Namespace",
          metadata: {
            name: this.NAMESPACE,
            annotations: {
              name: this.NAMESPACE,
            },
          },
        },
      ],
    });
  }

  private createCloudWatchAgent(cwaTag: string) {
    const cloudwatchAgentSAName = "cloudwatch-agent";
    const cloudwatchAgentSA = this.createServiceAccount(cloudwatchAgentSAName);

    cloudwatchAgentSA.node.addDependency(this.cloudWatchNamespace);

    const cwAgentConfigmapData = {
      agent: {
        region: this.region,
      },
      logs: {
        metrics_collected: {
          kubernetes: {
            cluster_name: this.clusterManager.cluster.clusterName,
            metrics_collection_interval: 60,
          },
        },
        force_flush_interval: 5,
      },
    };
    const cloudwatchagentconfigmap = {
      apiVersion: "v1",
      kind: "ConfigMap",
      metadata: {
        name: "cwagentconfig",
        namespace: this.NAMESPACE,
      },
      data: {
        "cwagentconfig.json": this.toJsonString(cwAgentConfigmapData),
      },
    };

    const cw_agent_config_map = new eks.KubernetesManifest(
      this,
      "cwAgentConfigMap",
      {
        cluster: this.clusterManager.cluster,
        manifest: [cloudwatchagentconfigmap],
      }
    );
    cw_agent_config_map.node.addDependency(
      this.cloudWatchNamespace,
      cloudwatchAgentSA
    );

    const cloudwatchagentrole = {
      apiVersion: "rbac.authorization.k8s.io/v1",
      kind: "ClusterRole",
      metadata: { name: "cloudwatch-agent-role" },
      rules: [
        {
          apiGroups: [""],
          resources: ["pods", "nodes", "endpoints"],
          verbs: ["list", "watch"],
        },
        {
          apiGroups: ["apps"],
          resources: ["replicasets"],
          verbs: ["list", "watch"],
        },
        {
          apiGroups: ["batch"],
          resources: ["jobs"],
          verbs: ["list", "watch"],
        },
        {
          apiGroups: [""],
          resources: ["nodes/proxy"],
          verbs: ["get"],
        },
        {
          apiGroups: [""],
          resources: ["nodes/stats", "configmaps", "events"],
          verbs: ["create"],
        },
        {
          apiGroups: [""],
          resources: ["configmaps"],
          resourceNames: ["cwagent-clusterleader"],
          verbs: ["get", "update"],
        },
      ],
    };
    const cw_agent_role = new eks.KubernetesManifest(this, "cw_agent_role", {
      cluster: this.clusterManager.cluster,
      manifest: [cloudwatchagentrole],
    });
    cw_agent_role.node.addDependency(
      this.cloudWatchNamespace,
      cloudwatchAgentSA
    );

    const cloudwatchagentrolebinding = {
      apiVersion: "rbac.authorization.k8s.io/v1",
      kind: "ClusterRoleBinding",
      metadata: {
        name: "cloudwatch-agent-role-binding",
      },
      subjects: [
        {
          kind: "ServiceAccount",
          name: "cloudwatch-agent",
          namespace: this.NAMESPACE,
        },
      ],
      roleRef: {
        kind: "ClusterRole",
        name: "cloudwatch-agent-role",
        apiGroup: "rbac.authorization.k8s.io",
      },
    };

    const cw_agent_role_binding = new eks.KubernetesManifest(
      this,
      "cwAgentRoleBinding",
      {
        cluster: this.clusterManager.cluster,
        manifest: [cloudwatchagentrolebinding],
      }
    );
    cw_agent_role_binding.node.addDependency(
      this.cloudWatchNamespace,
      cloudwatchAgentSA
    );

    const cwAgentSecretName = new eks.KubernetesObjectValue(
      this,
      "CloudWatchAgentSASecretName",
      {
        cluster: this.clusterManager.cluster,
        objectType: "serviceAccounts",
        objectName: "cloudwatch-agent",
        objectNamespace: this.NAMESPACE,
        timeout: cdk.Duration.minutes(1),
        jsonPath: ".secrets[0].name",
      }
    ).value;

    const cloudwatchagentdeamonset = {
      apiVersion: "apps/v1",
      kind: "DaemonSet",
      metadata: {
        name: "cloudwatch-agent",
        namespace: this.NAMESPACE,
      },
      spec: {
        selector: {
          matchLabels: {
            name: "cloudwatch-agent",
          },
        },
        template: {
          metadata: {
            labels: {
              name: "cloudwatch-agent",
            },
          },
          spec: {
            volumes: [
              {
                name: "cwagentconfig",
                configMap: {
                  name: "cwagentconfig",
                },
              },
              {
                name: "rootfs",
                hostPath: {
                  path: "/",
                },
              },
              {
                name: "dockersock",
                hostPath: {
                  path: "/var/run/docker.sock",
                },
              },
              {
                name: "varlibdocker",
                hostPath: {
                  path: "/var/lib/docker",
                },
              },
              {
                name: "sys",
                hostPath: {
                  path: "/sys",
                },
              },
              {
                name: "devdisk",
                hostPath: {
                  path: "/dev/disk/",
                },
              },
              {
                name: cwAgentSecretName,
                secret: {
                  secretName: cwAgentSecretName,
                },
              },
            ],
            containers: [
              {
                name: "cloudwatch-agent",
                image: `${this.account}.dkr.ecr.${this.region}.amazonaws.com/amazon/cloudwatch-agent:${cwaTag}`,
                env: [
                  {
                    name: "HOST_IP",
                    valueFrom: {
                      fieldRef: {
                        fieldPath: "status.hostIP",
                      },
                    },
                  },
                  {
                    name: "HOST_NAME",
                    valueFrom: {
                      fieldRef: {
                        fieldPath: "spec.nodeName",
                      },
                    },
                  },
                  {
                    name: "K8S_NAMESPACE",
                    valueFrom: {
                      fieldRef: {
                        fieldPath: "metadata.namespace",
                      },
                    },
                  },
                  {
                    name: "CI_VERSION",
                    value: "k8s/1.3.5",
                  },
                ],
                resources: {
                  limits: {
                    cpu: "200m",
                    memory: "200Mi",
                  },
                  requests: {
                    memory: "200Mi",
                    cpu: "200m",
                  },
                },
                volumeMounts: [
                  {
                    name: "cwagentconfig",
                    mountPath: "/etc/cwagentconfig",
                  },
                  {
                    name: "rootfs",
                    readOnly: true,
                    mountPath: "/rootfs",
                  },
                  {
                    name: "dockersock",
                    readOnly: true,
                    mountPath: "/var/run/docker.sock",
                  },
                  {
                    name: "varlibdocker",
                    readOnly: true,
                    mountPath: "/var/lib/docker",
                  },
                  {
                    name: "sys",
                    readOnly: true,
                    mountPath: "/sys",
                  },
                  {
                    name: "devdisk",
                    readOnly: true,
                    mountPath: "/dev/disk",
                  },
                  {
                    name: cwAgentSecretName,
                    readOnly: true,
                    mountPath: "/var/run/secrets/kubernetes.io/serviceaccount",
                  },
                ],
              },
            ],
            terminationGracePeriodSeconds: 60,
            serviceAccountName: "cloudwatch-agent",
          },
        },
      },
    };

    const cwAgentDeamonsetManifest = new eks.KubernetesManifest(
      this,
      "cwAgentDeamonsetManifest",
      {
        cluster: this.clusterManager.cluster,
        manifest: [cloudwatchagentdeamonset],
      }
    );
    cwAgentDeamonsetManifest.node.addDependency(
      this.cloudWatchNamespace,
      cloudwatchAgentSA,
      cw_agent_config_map
    );
  }

  private createFluentBit(awsForFluentBitTag: string) {
    const fluentBitConfigMap = {
      apiVersion: "v1",
      kind: "ConfigMap",
      metadata: {
        name: "fluent-bit-cluster-info",
        namespace: this.NAMESPACE,
      },
      data: {
        "cluster.name": this.clusterManager.cluster.clusterName,
        "http.port": "2020",
        "http.server": "On",
        "logs.region": this.region,
        "read.head": "Off",
        "read.tail": "On",
      },
    };

    const fluentBitConfigMapManifest = new eks.KubernetesManifest(
      this,
      "fluentBitConfigMapManifest",
      {
        cluster: this.clusterManager.cluster,
        manifest: [fluentBitConfigMap],
      }
    );
    fluentBitConfigMapManifest.node.addDependency(this.cloudWatchNamespace);

    const fluentBitSAName = "fluent-bit";
    const fluentBitSA = this.createServiceAccount(fluentBitSAName);

    fluentBitSA.node.addDependency(this.cloudWatchNamespace);

    const fluentBitRole = {
      apiVersion: "rbac.authorization.k8s.io/v1",
      kind: "ClusterRole",
      metadata: { name: "fluent-bit-role" },
      rules: [
        {
          verbs: ["get"],
          nonResourceURLs: ["/metrics"],
        },
        {
          apiGroups: [""],
          resources: ["namespaces", "pods", "pods/logs"],
          verbs: ["get", "list", "watch"],
        },
      ],
    };
    const fluentBitRoleManifest = new eks.KubernetesManifest(
      this,
      "fluentBitRoleManifest",
      {
        cluster: this.clusterManager.cluster,
        manifest: [fluentBitRole],
      }
    );
    fluentBitRoleManifest.node.addDependency(this.cloudWatchNamespace);

    const fluentBitRoleBinding = {
      apiVersion: "rbac.authorization.k8s.io/v1",
      kind: "ClusterRoleBinding",
      metadata: {
        name: "fluent-bit-role-binding",
      },
      subjects: [
        {
          kind: "ServiceAccount",
          name: "fluent-bit",
          namespace: this.NAMESPACE,
        },
      ],
      roleRef: {
        kind: "ClusterRole",
        name: "fluent-bit-role",
        apiGroup: "rbac.authorization.k8s.io",
      },
    };

    const fluentBitRoleBindingManifest = new eks.KubernetesManifest(
      this,
      "fluentBitRoleBindingManifest",
      {
        cluster: this.clusterManager.cluster,
        manifest: [fluentBitRoleBinding],
      }
    );
    fluentBitRoleBindingManifest.node.addDependency(
      this.cloudWatchNamespace,
      fluentBitSA
    );

    const fluentBitConfigsAppLog =
      "[INPUT]\n    Name                tail\n    Tag                 application.*\n    Exclude_Path        /var/log/containers/cloudwatch-agent*, /var/log/containers/fluent-bit*, /var/log/containers/aws-node*, /var/log/containers/kube-proxy*\n    Path                /var/log/containers/*.log\n    Docker_Mode         On\n    Docker_Mode_Flush   5\n    Docker_Mode_Parser  container_firstline\n    Parser              docker\n    DB                  /var/fluent-bit/state/flb_container.db\n    Mem_Buf_Limit       50MB\n    Skip_Long_Lines     On\n    Refresh_Interval    10\n    Rotate_Wait         30\n    storage.type        filesystem\n    Read_from_Head      ${READ_FROM_HEAD}\n\n[INPUT]\n    Name                tail\n    Tag                 application.*\n    Path                /var/log/containers/fluent-bit*\n    Parser              docker\n    DB                  /var/fluent-bit/state/flb_log.db\n    Mem_Buf_Limit       5MB\n    Skip_Long_Lines     On\n    Refresh_Interval    10\n    Read_from_Head      ${READ_FROM_HEAD}\n\n[INPUT]\n    Name                tail\n    Tag                 application.*\n    Path                /var/log/containers/cloudwatch-agent*\n    Docker_Mode         On\n    Docker_Mode_Flush   5\n    Docker_Mode_Parser  cwagent_firstline\n    Parser              docker\n    DB                  /var/fluent-bit/state/flb_cwagent.db\n    Mem_Buf_Limit       5MB\n    Skip_Long_Lines     On\n    Refresh_Interval    10\n    Read_from_Head      ${READ_FROM_HEAD}\n\n[FILTER]\n    Name                kubernetes\n    Match               application.*\n    Kube_URL            https://kubernetes.default.svc:443\n    Kube_Tag_Prefix     application.var.log.containers.\n    Merge_Log           On\n    Merge_Log_Key       log_processed\n    K8S-Logging.Parser  On\n    K8S-Logging.Exclude Off\n    Labels              Off\n    Annotations         Off\n\n[OUTPUT]\n    Name                cloudwatch_logs\n    Match               application.*\n    region              ${AWS_REGION}\n    log_group_name      /aws/containerinsights/${CLUSTER_NAME}/application\n    log_stream_prefix   ${HOST_NAME}-\n    auto_create_group   true\n    extra_user_agent    container-insights\n";
    const fluentBitConfigsDataLog =
      "[INPUT]\n    Name                systemd\n    Tag                 dataplane.systemd.*\n    Systemd_Filter      _SYSTEMD_UNIT=docker.service\n    DB                  /var/fluent-bit/state/systemd.db\n    Path                /var/log/journal\n    Read_From_Tail      ${READ_FROM_TAIL}\n\n[INPUT]\n    Name                tail\n    Tag                 dataplane.tail.*\n    Path                /var/log/containers/aws-node*, /var/log/containers/kube-proxy*\n    Docker_Mode         On\n    Docker_Mode_Flush   5\n    Docker_Mode_Parser  container_firstline\n    Parser              docker\n    DB                  /var/fluent-bit/state/flb_dataplane_tail.db\n    Mem_Buf_Limit       50MB\n    Skip_Long_Lines     On\n    Refresh_Interval    10\n    Rotate_Wait         30\n    storage.type        filesystem\n    Read_from_Head      ${READ_FROM_HEAD}\n\n[FILTER]\n    Name                modify\n    Match               dataplane.systemd.*\n    Rename              _HOSTNAME                   hostname\n    Rename              _SYSTEMD_UNIT               systemd_unit\n    Rename              MESSAGE                     message\n    Remove_regex        ^((?!hostname|systemd_unit|message).)*$\n\n[FILTER]\n    Name                aws\n    Match               dataplane.*\n    imds_version        v1\n\n[OUTPUT]\n    Name                cloudwatch_logs\n    Match               dataplane.*\n    region              ${AWS_REGION}\n    log_group_name      /aws/containerinsights/${CLUSTER_NAME}/dataplane\n    log_stream_prefix   ${HOST_NAME}-\n    auto_create_group   true\n    extra_user_agent    container-insights\n";
    const fluentBitConfigsFluentBit =
      "[SERVICE]\n    Flush                     5\n    Log_Level                 info\n    Daemon                    off\n    Parsers_File              parsers.conf\n    HTTP_Server               ${HTTP_SERVER}\n    HTTP_Listen               0.0.0.0\n    HTTP_Port                 ${HTTP_PORT}\n    storage.path              /var/fluent-bit/state/flb-storage/\n    storage.sync              normal\n    storage.checksum          off\n    storage.backlog.mem_limit 5M\n    \n@INCLUDE application-log.conf\n@INCLUDE dataplane-log.conf\n@INCLUDE host-log.conf\n";
    const fluentBitConfigsHostLog =
      "[INPUT]\n    Name                tail\n    Tag                 host.dmesg\n    Path                /var/log/dmesg\n    Parser              syslog\n    DB                  /var/fluent-bit/state/flb_dmesg.db\n    Mem_Buf_Limit       5MB\n    Skip_Long_Lines     On\n    Refresh_Interval    10\n    Read_from_Head      ${READ_FROM_HEAD}\n\n[INPUT]\n    Name                tail\n    Tag                 host.messages\n    Path                /var/log/messages\n    Parser              syslog\n    DB                  /var/fluent-bit/state/flb_messages.db\n    Mem_Buf_Limit       5MB\n    Skip_Long_Lines     On\n    Refresh_Interval    10\n    Read_from_Head      ${READ_FROM_HEAD}\n\n[INPUT]\n    Name                tail\n    Tag                 host.secure\n    Path                /var/log/secure\n    Parser              syslog\n    DB                  /var/fluent-bit/state/flb_secure.db\n    Mem_Buf_Limit       5MB\n    Skip_Long_Lines     On\n    Refresh_Interval    10\n    Read_from_Head      ${READ_FROM_HEAD}\n\n[FILTER]\n    Name                aws\n    Match               host.*\n    imds_version        v1\n\n[OUTPUT]\n    Name                cloudwatch_logs\n    Match               host.*\n    region              ${AWS_REGION}\n    log_group_name      /aws/containerinsights/${CLUSTER_NAME}/host\n    log_stream_prefix   ${HOST_NAME}.\n    auto_create_group   true\n    extra_user_agent    container-insights\n";
    const fluentBitConfigsParsers =
      "[PARSER]\n    Name                docker\n    Format              json\n    Time_Key            time\n    Time_Format         %Y-%m-%dT%H:%M:%S.%LZ\n\n[PARSER]\n    Name                syslog\n    Format              regex\n    Regex               ^(?<time>[^ ]* {1,2}[^ ]* [^ ]*) (?<host>[^ ]*) (?<ident>[a-zA-Z0-9_\\/\\.\\-]*)(?:\\[(?<pid>[0-9]+)\\])?(?:[^\\:]*\\:)? *(?<message>.*)$\n    Time_Key            time\n    Time_Format         %b %d %H:%M:%S\n\n[PARSER]\n    Name                container_firstline\n    Format              regex\n    Regex               (?<log>(?<=\"log\":\")\\S(?!\\.).*?)(?<!\\\\)\".*(?<stream>(?<=\"stream\":\").*?)\".*(?<time>\\d{4}-\\d{1,2}-\\d{1,2}T\\d{2}:\\d{2}:\\d{2}\\.\\w*).*(?=})\n    Time_Key            time\n    Time_Format         %Y-%m-%dT%H:%M:%S.%LZ\n\n[PARSER]\n    Name                cwagent_firstline\n    Format              regex\n    Regex               (?<log>(?<=\"log\":\")\\d{4}[\\/-]\\d{1,2}[\\/-]\\d{1,2}[ T]\\d{2}:\\d{2}:\\d{2}(?!\\.).*?)(?<!\\\\)\".*(?<stream>(?<=\"stream\":\").*?)\".*(?<time>\\d{4}-\\d{1,2}-\\d{1,2}T\\d{2}:\\d{2}:\\d{2}\\.\\w*).*(?=})\n    Time_Key            time\n    Time_Format         %Y-%m-%dT%H:%M:%S.%LZ\n";

    const fluentBitConfigsConfigMap = {
      apiVersion: "v1",
      kind: "ConfigMap",
      metadata: {
        name: "fluent-bit-config",
        namespace: this.NAMESPACE,
        labels: {
          "k8s-app": "fluent-bit",
        },
      },
      data: {
        "application-log.conf": fluentBitConfigsAppLog,
        "dataplane-log.conf": fluentBitConfigsDataLog,
        "fluent-bit.conf": fluentBitConfigsFluentBit,
        "host-log.conf": fluentBitConfigsHostLog,
        "parsers.conf": fluentBitConfigsParsers,
      },
    };

    const fluentBitConfigsConfigMapManifest = new eks.KubernetesManifest(
      this,
      "fluentBitConfigsConfigMap",
      {
        cluster: this.clusterManager.cluster,
        manifest: [fluentBitConfigsConfigMap],
      }
    );
    fluentBitConfigsConfigMapManifest.node.addDependency(
      this.cloudWatchNamespace
    );

    const fluentBitSecretName = new eks.KubernetesObjectValue(
      this,
      "FluentBitSASecretName",
      {
        cluster: this.clusterManager.cluster,
        objectType: "serviceAccounts",
        objectName: "fluent-bit",
        objectNamespace: this.NAMESPACE,
        timeout: cdk.Duration.minutes(1),
        jsonPath: ".secrets[0].name",
      }
    ).value;

    const fluentBitDeamonset = {
      apiVersion: "apps/v1",
      kind: "DaemonSet",
      metadata: {
        name: "fluent-bit",
        namespace: this.NAMESPACE,
        labels: {
          "k8s-app": "fluent-bit",
          "kubernetes.io/cluster-service": "true",
          version: "v1",
        },
      },
      spec: {
        selector: {
          matchLabels: {
            "k8s-app": "fluent-bit",
          },
        },
        template: {
          metadata: {
            labels: {
              "k8s-app": "fluent-bit",
              "kubernetes.io/cluster-service": "true",
              version: "v1",
            },
          },
          spec: {
            volumes: [
              {
                name: "fluentbitstate",
                hostPath: {
                  path: "/var/fluent-bit/state",
                },
              },
              {
                name: "varlog",
                hostPath: {
                  path: "/var/log",
                },
              },
              {
                name: "varlibdockercontainers",
                hostPath: {
                  path: "/var/lib/docker/containers",
                },
              },
              {
                name: "fluent-bit-config",
                configMap: {
                  name: "fluent-bit-config",
                },
              },
              {
                name: "runlogjournal",
                hostPath: {
                  path: "/run/log/journal",
                },
              },
              {
                name: "dmesg",
                hostPath: {
                  path: "/var/log/dmesg",
                },
              },
              {
                name: fluentBitSecretName,
                secret: {
                  secretName: fluentBitSecretName,
                },
              },
            ],
            containers: [
              {
                name: "fluent-bit",
                image: `${this.account}.dkr.ecr.${this.region}.amazonaws.com/aws-for-fluent-bit:${awsForFluentBitTag}`,
                imagePullPolicy: "Always",
                env: [
                  {
                    name: "AWS_REGION",
                    valueFrom: {
                      configMapKeyRef: {
                        name: "fluent-bit-cluster-info",
                        key: "logs.region",
                      },
                    },
                  },
                  {
                    name: "CLUSTER_NAME",
                    valueFrom: {
                      configMapKeyRef: {
                        name: "fluent-bit-cluster-info",
                        key: "cluster.name",
                      },
                    },
                  },
                  {
                    name: "HTTP_SERVER",
                    valueFrom: {
                      configMapKeyRef: {
                        name: "fluent-bit-cluster-info",
                        key: "http.server",
                      },
                    },
                  },
                  {
                    name: "HTTP_PORT",
                    valueFrom: {
                      configMapKeyRef: {
                        name: "fluent-bit-cluster-info",
                        key: "http.port",
                      },
                    },
                  },
                  {
                    name: "READ_FROM_HEAD",
                    valueFrom: {
                      configMapKeyRef: {
                        name: "fluent-bit-cluster-info",
                        key: "read.head",
                      },
                    },
                  },
                  {
                    name: "READ_FROM_TAIL",
                    valueFrom: {
                      configMapKeyRef: {
                        name: "fluent-bit-cluster-info",
                        key: "read.tail",
                      },
                    },
                  },
                  {
                    name: "HOST_NAME",
                    valueFrom: {
                      fieldRef: {
                        fieldPath: "spec.nodeName",
                      },
                    },
                  },
                  {
                    name: "CI_VERSION",
                    value: "k8s/1.3.5",
                  },
                ],
                resources: {
                  limits: {
                    memory: "200Mi",
                  },
                  requests: {
                    memory: "100Mi",
                    cpu: "500m",
                  },
                },
                volumeMounts: [
                  {
                    name: "fluentbitstate",
                    mountPath: "/var/fluent-bit/state",
                  },
                  {
                    name: "varlog",
                    readOnly: true,
                    mountPath: "/var/log",
                  },
                  {
                    name: "varlibdockercontainers",
                    readOnly: true,
                    mountPath: "/var/lib/docker/containers",
                  },
                  {
                    name: "fluent-bit-config",
                    mountPath: "/fluent-bit/etc/",
                  },
                  {
                    name: "runlogjournal",
                    readOnly: true,
                    mountPath: "/run/log/journal",
                  },
                  {
                    name: "dmesg",
                    readOnly: true,
                    mountPath: "/var/log/dmesg",
                  },
                  {
                    name: fluentBitSecretName,
                    readOnly: true,
                    mountPath: "/var/run/secrets/kubernetes.io/serviceaccount",
                  },
                ],
              },
            ],
            terminationGracePeriodSeconds: 10,
            serviceAccountName: "fluent-bit",
            tolerations: [
              {
                key: "node-role.kubernetes.io/master",
                operator: "Exists",
                effect: "NoSchedule",
              },
              {
                operator: "Exists",
                effect: "NoExecute",
              },
              {
                operator: "Exists",
                effect: "NoSchedule",
              },
            ],
          },
        },
      },
    };

    const fluentBitDeamonsetManifest = new eks.KubernetesManifest(
      this,
      "fluentBitDeamonsetManifest",
      {
        cluster: this.clusterManager.cluster,
        manifest: [fluentBitDeamonset],
      }
    );
    fluentBitDeamonsetManifest.node.addDependency(
      this.cloudWatchNamespace,
      fluentBitSA
    );
  }

  // Need to manually create to avoid circular dependency + having ICluster vs Cluster
  // Stops taken from CDK doc: https://github.com/aws/aws-cdk/blob/a4f04186f2448fdf5c8d85f7733c05fd84940738/packages/%40aws-cdk/aws-eks/lib/service-account.ts#L41
  private createServiceAccount(saName: string): eks.KubernetesManifest {
    const cluster = this.clusterManager.cluster;
    // Merged from clemerey fixes
    // const conditions = new cdk.CfnJson(this, `${saName}ConditionJson`, {
    //   value: {
    //     [`${cluster.openIdConnectProvider.openIdConnectProviderIssuer}:aud`]: 'sts.amazonaws.com',
    //     [`${cluster.openIdConnectProvider.openIdConnectProviderIssuer}:sub`]: `system:serviceaccount:${this.NAMESPACE}:${saName}`,
    //   },
    // });
    // const principal = new iam.OpenIdConnectPrincipal(cluster.openIdConnectProvider).withConditions({
    //   StringEquals: conditions,
    // });
    // const role = new iam.Role(this, `${saName}Role`, { assumedBy: principal });

    return new eks.KubernetesManifest(
      this,
      `manifest-${saName}ServiceAccountResource`,
      {
        cluster,
        manifest: [
          {
            apiVersion: "v1",
            kind: "ServiceAccount",
            metadata: {
              name: saName,
              namespace: this.NAMESPACE,
              labels: {
                "app.kubernetes.io/name": saName,
                // },
                // annotations: {
                //   'eks.amazonaws.com/role-arn': role.roleArn,
              },
            },
          },
        ],
      }
    );
  }
}
