# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

locals {
  cognito_domain_name = replace("${lower(var.suffix)}-${random_string.random_resources.result}","aws","")
}

resource "aws_cognito_user_pool" "htc_pool" {
  name = "htc_pool"
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
}

resource "aws_cognito_user_pool_client" "client" {
  name = "client"

  user_pool_id = aws_cognito_user_pool.htc_pool.id
  allowed_oauth_flows_user_pool_client = true
  generate_secret     = true
  allowed_oauth_flows = ["code"]
  callback_urls  = ["https://${kubernetes_ingress_v1.grafana_ingress.status.0.load_balancer.0.ingress.0.hostname}/oauth2/idpresponse"]
  //callback_urls = ["https://example.com"]
  allowed_oauth_scopes = [
    "email", "openid"
  ]
  supported_identity_providers = [
    "COGNITO",
  ]
  explicit_auth_flows = [
    "ALLOW_ADMIN_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

}

resource "aws_cognito_user_pool_client" "user_data_client" {
  name = "user_data_client"

  user_pool_id = aws_cognito_user_pool.htc_pool.id

  explicit_auth_flows = [
    "ALLOW_ADMIN_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

}

resource "null_resource" "modify_ingress" {
  provisioner "local-exec" {
    command = "kubectl -n grafana annotate ingress grafana-ingress --overwrite alb.ingress.kubernetes.io/auth-idp-cognito=\"{\\\"UserPoolArn\\\": \\\"${aws_cognito_user_pool.htc_pool.arn}\\\",\\\"UserPoolClientId\\\":\\\"${aws_cognito_user_pool_client.client.id}\\\",\\\"UserPoolDomain\\\":\\\"${local.cognito_domain_name}\\\"}\" alb.ingress.kubernetes.io/auth-on-unauthenticated-reques=authenticate alb.ingress.kubernetes.io/auth-scope=openid alb.ingress.kubernetes.io/auth-session-cookie=AWSELBAuthSessionCookie alb.ingress.kubernetes.io/auth-session-timeout=\"3600\" alb.ingress.kubernetes.io/auth-type=cognito"
  }
  depends_on = [
    module.eks_blueprints_kubernetes_addons,
    kubernetes_ingress_v1.grafana_ingress
  ]
}


resource "aws_cognito_user_pool_domain" "domain" {

  domain       = local.cognito_domain_name
  user_pool_id = aws_cognito_user_pool.htc_pool.id
}
