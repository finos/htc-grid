// Copyright 2022 Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


import { Construct } from "constructs";
import * as cdk from "aws-cdk-lib";
import * as cognito from "aws-cdk-lib/aws-cognito";
import * as eks from "aws-cdk-lib/aws-eks";
import { ClusterManagerPlus } from "../shared/cluster-manager-plus/cluster-manager-plus";


export interface CognitoAuthStackProps extends cdk.StackProps {
  readonly clusterManager: ClusterManagerPlus;
  readonly projectName: string
}
export class CognitoAuthStack extends cdk.Stack {
  public readonly cognito_userpool: cognito.IUserPool;
  public readonly cognito_userpool_client: cognito.IUserPoolClient;
  private clusterManager: ClusterManagerPlus;
  private project_name : string ;

  constructor(scope: Construct, id: string, props: CognitoAuthStackProps) {
    super(scope, id, props);

    const domainName = `${this.project_name}-${this.node.addr.substring(0, 5)}`
    this.clusterManager = props.clusterManager;
    this.project_name = props.projectName ;
    this.cognito_userpool = new cognito.UserPool(this, "htc_pool", {
      userPoolName: "htc_pool",
      selfSignUpEnabled: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });
    this.cognito_userpool_client = this.createClients(domainName);
    this.cognito_userpool.addDomain("htc_userpool_domain", {
      cognitoDomain: {
        domainPrefix: domainName,
      },
    });
  }

  private createClients(domainName: string): cognito.IUserPoolClient {
    const grafanaAddress = new eks.KubernetesObjectValue(
      this,
      "GrafanaIngressAddress",
      {
        cluster: this.clusterManager.cluster,
        // objectType: 'ingress',
        objectType: "ingresses.v1.networking.k8s.io", // need to be specific until k8s version is updated
        objectName: "grafana-ingress",
        objectNamespace: "grafana",
        timeout: cdk.Duration.minutes(1),
        jsonPath: ".status.loadBalancer.ingress[0].hostname",
      }
    ).value;

    const userPoolClient = new cognito.UserPoolClient(this, "htc_client", {
      userPool: this.cognito_userpool,
      userPoolClientName: "client",
      disableOAuth: false,
      generateSecret: true,
      oAuth: {
        flows: {
          authorizationCodeGrant: true,
        },
        scopes: [cognito.OAuthScope.EMAIL, cognito.OAuthScope.OPENID],
        callbackUrls: [`https://${grafanaAddress}/oauth2/idpresponse`],
      },
      supportedIdentityProviders: [
        cognito.UserPoolClientIdentityProvider.COGNITO,
      ],
      authFlows: {
        adminUserPassword: true,
        userSrp: true,
        //ALLOW_REFRESH_TOKEN_AUTH
      },
    });
    const userPoolDataClient = new cognito.UserPoolClient(this, "htc_data_client", {
      userPool: this.cognito_userpool,
      userPoolClientName: "user_data_client",
      authFlows: {
        adminUserPassword: true,
        userSrp: true,
        //ALLOW_REFRESH_TOKEN_AUTH
      },
    });

    this.clusterManager.customKubectl(this, {
      kubectlCreateCmd: `-n grafana annotate ingress grafana-ingress --overwrite alb.ingress.kubernetes.io/auth-idp-cognito="{\\"UserPoolArn\\": \\"${this.cognito_userpool.userPoolArn}\\",\\"UserPoolClientId\\":\\"${userPoolClient.userPoolClientId}\\",\\"UserPoolDomain\\":\\"${domainName}\\"}" alb.ingress.kubernetes.io/auth-on-unauthenticated-reques=authenticate alb.ingress.kubernetes.io/auth-scope=openid alb.ingress.kubernetes.io/auth-session-cookie=AWSELBAuthSessionCookie alb.ingress.kubernetes.io/auth-session-timeout="3600" alb.ingress.kubernetes.io/auth-type=cognito`,
    });
    return userPoolDataClient;
  }
}
