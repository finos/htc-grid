# Copyright 2023 Amazon.com, Inc. or its affiliates. 
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
