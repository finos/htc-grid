# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


locals {
  cognito_domain_name = replace("${lower(var.suffix)}-${random_string.random.result}", "aws", "")
}


resource "aws_cognito_user_pool" "htc_pool" {
  name = "htc_pool"
  account_recovery_setting {
    recovery_mechanism {
      name     = "admin_only"
      priority = 1
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = true
  }
}


resource "aws_cognito_user_pool_domain" "domain" {
  user_pool_id = aws_cognito_user_pool.htc_pool.id
  domain       = local.cognito_domain_name
}


resource "aws_cognito_user_pool_client" "user_data_client" {
  name         = "user_data_client"
  user_pool_id = aws_cognito_user_pool.htc_pool.id
  explicit_auth_flows = [
    "ALLOW_ADMIN_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
}


resource "aws_cognito_user_pool_client" "client" {
  name                                 = "client"
  user_pool_id                         = aws_cognito_user_pool.htc_pool.id
  allowed_oauth_flows_user_pool_client = true
  generate_secret                      = true
  allowed_oauth_flows                  = ["code"]
  callback_urls                        = ["https://${data.kubernetes_ingress_v1.grafana_ingress.status.0.load_balancer.0.ingress.0.hostname}/oauth2/idpresponse"]
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


resource "aws_cognito_user" "grafana_admin" {
  user_pool_id       = aws_cognito_user_pool.htc_pool.id
  username           = "admin"
  temporary_password = var.grafana_admin_password
}


resource "null_resource" "grafana_ingress_auth" {
  triggers = {
    user_pool_arn          = aws_cognito_user_pool.htc_pool.arn
    client_id              = aws_cognito_user_pool_client.client.id
    cognito_domain         = local.cognito_domain_name
    grafana_domain_name    = data.kubernetes_ingress_v1.grafana_ingress.status.0.load_balancer.0.ingress.0.hostname
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl -n grafana annotate ingress grafana --overwrite \
        alb.ingress.kubernetes.io/auth-idp-cognito="{\"UserPoolArn\": \"${self.triggers.user_pool_arn}\",\"UserPoolClientId\":\"${self.triggers.client_id}\",\"UserPoolDomain\":\"${self.triggers.cognito_domain}\"}" \
        alb.ingress.kubernetes.io/auth-on-unauthenticated-request=authenticate \
        alb.ingress.kubernetes.io/auth-scope=openid \
        alb.ingress.kubernetes.io/auth-session-cookie=AWSELBAuthSessionCookie \
        alb.ingress.kubernetes.io/auth-session-timeout="3600" \
        alb.ingress.kubernetes.io/auth-type=cognito
    EOT
  }

  provisioner "local-exec" {
    when       = destroy
    command    = <<-EOT
      kubectl -n grafana annotate ingress grafana \
        alb.ingress.kubernetes.io/auth-idp-cognito- \
        alb.ingress.kubernetes.io/auth-on-unauthenticated-request- \
        alb.ingress.kubernetes.io/auth-scope- \
        alb.ingress.kubernetes.io/auth-session-cookie- \
        alb.ingress.kubernetes.io/auth-session-timeout- \
        alb.ingress.kubernetes.io/auth-type-
    EOT
    on_failure = continue
  }

  depends_on = [
    module.eks,
    module.eks_blueprints_addons,
    data.kubernetes_ingress_v1.grafana_ingress,
    null_resource.update_kubeconfig
  ]
}
