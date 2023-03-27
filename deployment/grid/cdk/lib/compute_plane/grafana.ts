// Copyright 2022 Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


// Namespace: grafana

import { Construct } from "constructs";
import * as cdk from "aws-cdk-lib";
import * as path from "path";
import * as fs from "fs";
import * as yaml from 'yaml'
import * as forge from "node-forge";
import * as cr from "aws-cdk-lib/custom-resources";
import * as lambda from "aws-cdk-lib/aws-lambda";
import * as iam from "aws-cdk-lib/aws-iam";
import * as eks from "aws-cdk-lib/aws-eks";
import * as secretsmanager from"aws-cdk-lib/aws-secretsmanager";
import { ClusterManagerPlus } from "../shared/cluster-manager-plus/cluster-manager-plus";

interface GrafanaProps extends cdk.NestedStackProps {
  readonly clusterManager: ClusterManagerPlus;
  readonly grafanaAdminPassword: string;
  readonly busyboxTag: string;
  readonly grafanaTag: string;
  readonly curlTag: string;
  readonly k8sSideCarTag: string;
}

export class GrafanaStack extends cdk.NestedStack {
  public readonly albCertArn: string;
  public grafanaPasswordSecret: secretsmanager.ISecret ;
  constructor(scope: Construct, id: string, props: GrafanaProps) {
    super(scope, id, props);


    this.grafanaPasswordSecret = new secretsmanager.Secret(this, "Secret", {
      description: "Password required for login to the grafana dashboard",
      secretStringValue: cdk.SecretValue.unsafePlainText(props.grafanaAdminPassword)
    });

    const NAMESPACE = "grafana";
    const clusterManager = props.clusterManager;


    const htc_metrics_path = path.join(__dirname, "./htc-dashboard.json");
    const htc_metrics_data = fs.readFileSync(htc_metrics_path);
    const k8s_metrics_path = path.join(
      __dirname,
      "./kubernetes-dashboard.json"
    );
    const k8s_metrics_data = fs.readFileSync(k8s_metrics_path);

    const namespace_manifest = {
      apiVersion: "v1",
      kind: "Namespace",
      metadata: {
        name: NAMESPACE,
        annotations: {
          name: NAMESPACE,
        },
      },
    };
    const grafana_namespace = new eks.KubernetesManifest(
      this,
      "grafana-namespace",
      {
        cluster: clusterManager.cluster,
        manifest: [namespace_manifest],
      }
    );

    const grafanaPlacementConfiguration = yaml.parse(fs.readFileSync(path.join(__dirname, "./grafana_placement_conf.yaml")).toString())
    const grafanaDashboardConfiguration = yaml.parse(fs.readFileSync(path.join(__dirname, "./grafana_dashboard_k8s.yaml")).toString())
    const grafana = clusterManager.createHelmChart(this, {
      namespace: NAMESPACE,
      chart: "grafana",
      repository: "https://grafana.github.io/helm-charts/",
      release: "grafana",
      values: {
        ...grafanaPlacementConfiguration,
        ...grafanaDashboardConfiguration,
        persistence : {
          enabled: false
        },

        // if admin pw is blank, set it to default pw
        adminPassword: props.grafanaAdminPassword ?? "htcadmin",
        ingress: {
          annotations: {
            "alb.ingress.kubernetes.io/subnets" : clusterManager.cluster.vpc.privateSubnets.map(subnet => subnet.subnetId).join(","),
          }
        },
        initChownData : {
          image: {
            repository : `${this.account}.dkr.ecr.${this.region}.amazonaws.com/busybox`,
            tag : props.busyboxTag
          }
        },
        image: {
          repository: `${this.account}.dkr.ecr.${this.region}.amazonaws.com/grafana`,
          tag: props.grafanaTag
        },
        downloadDashboardsImage : {
          repository: `${this.account}.dkr.ecr.${this.region}.amazonaws.com/curl`,
          tag: props.curlTag,
        },
        sidecar : {
          dashboards: {
            enabled: true
          },
          image : {
            tag:props.k8sSideCarTag,
            repository: `${this.account}.dkr.ecr.${this.region}.amazonaws.com/k8s-sidecar`,
          }
        },
        service : {
          type: "NodePort"
        }
      },
    });

    grafana.node.addDependency(grafana_namespace);

    const alb_cert_resource = this.createSelfSignedCert();
    this.albCertArn = alb_cert_resource.getAttString("CertificateArn");

    const htc_dashboards_manifest = {
      apiVersion: "v1",
      kind: "ConfigMap",
      metadata: {
        namespace: "grafana",
        name: "grafana-dashboard",
        labels: {
          grafana_dashboard: "1",
        },
      },
      data: {
        "htc-metrics.json": htc_metrics_data.toString(),
        "kubernetes-metrics.json": k8s_metrics_data.toString(),
      },
    };

    const htc_dashboards = new eks.KubernetesManifest(this, "HtcDashboardDefinition",{
      cluster: clusterManager.cluster,
      manifest: [htc_dashboards_manifest]
    });

    htc_dashboards.node.addDependency(grafana_namespace);

    const ingressManifest = {
      apiVersion: "networking.k8s.io/v1",
      kind: "Ingress",
      metadata: {
        name: "grafana-ingress",
        namespace: "grafana",
        annotations: {
          "kubernetes.io/ingress.class": "alb",
          "alb.ingress.kubernetes.io/scheme": "internet-facing",
          "alb.ingress.kubernetes.io/listen-ports":
            "[{\"HTTP\": 80},{\"HTTPS\":443}]",
          "alb.ingress.kubernetes.io/certificate-arn": this.albCertArn,
          "alb.ingress.kubernetes.io/actions.ssl-redirect":
            "{\"Type\": \"redirect\", \"RedirectConfig\": { \"Protocol\": \"HTTPS\", \"Port\": \"443\", \"StatusCode\": \"HTTP_301\"}}",
          "alb.ingress.kubernetes.io/subnets" : clusterManager.cluster.vpc.publicSubnets.join(",")

        },
      },
      spec: {
        rules: [
          {
            http: {
              paths: [
                {
                  backend: {
                    service: {
                      name: "ssl-redirect",
                      port: {
                        name: "use-annotation",
                      },
                    },
                  },
                  pathType: "Prefix",
                  path: "/*",
                },
                {
                  backend: {
                    service: {
                      name: "grafana",
                      port: {
                        number: 80,
                      },
                    },
                  },
                  pathType: "Prefix",
                  path: "/*",
                },
              ],
            },
          },
        ],
      },
    };
    const ingressUpdate = new eks.KubernetesManifest(this, "albIngressUpdate", {
      cluster: clusterManager.cluster,
      manifest: [ingressManifest],
    });

    ingressUpdate.node.addDependency(grafana, grafana_namespace);
  }

  private createSelfSignedCert(): cdk.CustomResource {
    const keys = forge.pki.rsa.generateKeyPair(4096);
    const cert = forge.pki.createCertificate();
    cert.publicKey = keys.publicKey;
    cert.serialNumber = "01";
    cert.validity.notBefore = new Date();
    cert.validity.notAfter = new Date();
    cert.validity.notAfter.setHours(cert.validity.notBefore.getDay() + 12);
    const attrs = [
      {
        name: "commonName",
        value: "amazonaws.com",
      },
      {
        name: "countryName",
        value: "LU",
      },
      {
        name: "localityName",
        value: "LU",
      },
      {
        name: "organizationName",
        value: "AWS",
      },
      {
        shortName: "OU",
        value: "AWS",
      },
    ];
    cert.setSubject(attrs);
    cert.setIssuer(attrs);
    cert.setExtensions([
      {
        name: "keyUsage",
        keyEncipherment: true,
        digitalSignature: true,
        serverAuth: true,
      },
    ]);
    cert.sign(keys.privateKey);

    const private_key = forge.pki.privateKeyToPem(keys.privateKey);
    const self_signed_cert = forge.pki.certificateToPem(cert);

    const handler = new lambda.SingletonFunction(
      this,
      "SelfSignedCertHandler",
      {
        functionName: "GrafanaSelfSignedCertHandler",
        code: lambda.Code.fromAsset(
          path.join(__dirname, "../shared/cert-generator")
        ),
        runtime: lambda.Runtime.PYTHON_3_7,
        handler: "index.handler",
        timeout: cdk.Duration.minutes(1),
        uuid: "@aws-cdk/HtcSelfSignedCert",
        description: "onEvent handler for Htc Self Signed Cert provider",
      }
    );
    handler.role!.addToPrincipalPolicy(
      new iam.PolicyStatement({
        actions: ["acm:ImportCertificate", "acm:DeleteCertificate"],
        resources: ["*"],
      })
    );
    const provider = new cr.Provider(this, "SelfSignedCertProvider", {
      onEventHandler: handler,
    });

    return new cdk.CustomResource(this, "SelfSignedCertCR", {
      serviceToken: provider.serviceToken,
      properties: {
        Certificate: self_signed_cert,
        PrivateKey: private_key,
      },
    });
  }
}
