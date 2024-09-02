# Copyright 2023 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


module "htc_private_api_cloudwatch_kms_key" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 2.0"

  description             = "CMK KMS Key used to encrypt htc_private_api CloudWatch Logs"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true

  key_administrators = local.kms_key_admin_arns

  key_statements = [
    {
      sid = "Allow API Gateway to encrypt/decrypt CloudWatch Logs"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
        "kms:Decrypt",
      ]
      effect = "Allow"
      principals = [
        {
          type = "Service"
          identifiers = [
            "logs.${var.region}.${local.dns_suffix}"
          ]
        }
      ]
      resources = ["*"]
      conditions = [
        {
          test     = "ArnEquals"
          variable = "kms:EncryptionContext:aws:logs:arn"
          values   = ["arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:/aws/apigateway/htc-private-api-${var.cluster_name}-${var.api_gateway_version}"]
        }
      ]
    }
  ]

  aliases = ["cloudwatch/api/htc-private-api-${var.cluster_name}"]
}


resource "aws_cloudwatch_log_group" "htc_private_api_cloudwatch_log_group" {
  name              = "/aws/apigateway/htc-private-api-${var.cluster_name}-${var.api_gateway_version}"
  kms_key_id        = module.htc_private_api_cloudwatch_kms_key.key_arn
  retention_in_days = 365
}


resource "aws_api_gateway_rest_api" "htc_private_api" {
  #checkov:skip=CKV_AWS_237: Create before destroy already implemented in the deployment

  name = "htc-private-api-${var.cluster_name}"

  body = jsonencode(yamldecode(templatefile("../../../source/control_plane/openapi/private/api_definition.yaml", {
    region                  = var.region
    account_id              = data.aws_caller_identity.current.account_id
    cancel_lambda_name      = module.cancel_tasks.lambda_function_name
    submit_task_lambda_name = module.submit_task.lambda_function_name
    get_result_lambda_name  = module.get_results.lambda_function_name
  })))

  endpoint_configuration {
    types = ["PRIVATE"]
  }
}


resource "aws_api_gateway_deployment" "htc_private_api_deployment" {
  #checkov:skip=CKV_AWS_237: Create before destroy already implemented

  rest_api_id = aws_api_gateway_rest_api.htc_private_api.id

  triggers = {
    redeployment = templatefile("../../../source/control_plane/openapi/private/api_definition.yaml", {
      region                  = var.region
      account_id              = data.aws_caller_identity.current.account_id
      cancel_lambda_name      = module.cancel_tasks.lambda_function_name
      submit_task_lambda_name = module.submit_task.lambda_function_name
      get_result_lambda_name  = module.get_results.lambda_function_name
    })
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_rest_api_policy.htc_private_api_policy,
  ]
}


resource "aws_api_gateway_stage" "htc_private_api_stage" {
  #checkov:skip=CKV_AWS_120: API Gateway caching wouldn't work for this API
  #checkov:skip=CKV2_AWS_51:[TODO] Client certificate authentication will be implemented instead of Cognito

  rest_api_id   = aws_api_gateway_rest_api.htc_private_api.id
  deployment_id = aws_api_gateway_deployment.htc_private_api_deployment.id

  stage_name = var.api_gateway_version

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.htc_private_api_cloudwatch_log_group.arn
    format          = "$context.identity.sourceIp $context.identity.caller $context.identity.user $context.requestTime $context.httpMethod $context.resourcePath $context.protocol $context.status $context.responseLength $context.requestId $context.extendedRequestId"
  }

  xray_tracing_enabled = true

  depends_on = [
    aws_cloudwatch_log_group.htc_private_api_cloudwatch_log_group
  ]
}


resource "aws_api_gateway_method_settings" "htc_private_api_method_settings" {
  #checkov:skip=CKV_AWS_308: API Gateway method setting caching encryption wouldn't work for this API
  #checkov:skip=CKV_AWS_225: API Gateway method setting caching wouldn't work for this API

  rest_api_id = aws_api_gateway_rest_api.htc_private_api.id
  stage_name  = aws_api_gateway_stage.htc_private_api_stage.stage_name

  method_path = "*/*"

  settings {
    metrics_enabled = true
    logging_level   = "ERROR"
  }
}


resource "aws_api_gateway_api_key" "htc_private_api_key" {
  name = "htc-private-api-${var.cluster_name}"
}


resource "aws_api_gateway_usage_plan" "htc_private_api_usage_plan" {
  name = "htc-private-api-${var.cluster_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.htc_private_api.id
    stage  = aws_api_gateway_stage.htc_private_api_stage.stage_name
  }
}


resource "aws_api_gateway_usage_plan_key" "htc_private_api_usage_plan_key" {
  key_id        = aws_api_gateway_api_key.htc_private_api_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.htc_private_api_usage_plan.id
}


resource "aws_lambda_permission" "openapi_htc_private_apigw_private_lambda_permission_submit" {
  statement_id  = "AllowPrivateSubmitAPIGatewayInvoke-${local.suffix}"
  action        = "lambda:InvokeFunction"
  function_name = module.submit_task.lambda_function_name
  principal     = "apigateway.${local.dns_suffix}"

  # The "/*/*" portion grants access from any method on any resource
  # within the API Gateway REST API.
  source_arn = "${aws_api_gateway_rest_api.htc_private_api.execution_arn}/*/*"
}


resource "aws_lambda_permission" "openapi_htc_private_apigw_lambda_permission_result" {
  statement_id  = "AllowPrivateResultAPIGatewayInvoke-${local.suffix}"
  action        = "lambda:InvokeFunction"
  function_name = module.get_results.lambda_function_name
  principal     = "apigateway.${local.dns_suffix}"

  # The "/*/*" portion grants access from any method on any resource
  # within the API Gateway REST API.
  source_arn = "${aws_api_gateway_rest_api.htc_private_api.execution_arn}/*/*"
}


resource "aws_lambda_permission" "openapi_htc_private_apigw_private_lambda_permission_cancel" {
  statement_id  = "AllowPrivateCancelAPIGatewayInvoke-${local.suffix}"
  action        = "lambda:InvokeFunction"
  function_name = module.cancel_tasks.lambda_function_name
  principal     = "apigateway.${local.dns_suffix}"

  # The "/*/*" portion grants access from any method on any resource
  # within the API Gateway REST API.
  source_arn = "${aws_api_gateway_rest_api.htc_private_api.execution_arn}/*/*"
}


resource "aws_api_gateway_rest_api_policy" "htc_private_api_policy" {
  rest_api_id = aws_api_gateway_rest_api.htc_private_api.id

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": "*",
            "Action": "execute-api:Invoke",
            "Resource": [
                "${aws_api_gateway_rest_api.htc_private_api.execution_arn}/*"
            ]
        },
        {
            "Effect": "Deny",
            "Principal": "*",
            "Action": "execute-api:Invoke",
            "Resource": [
                "${aws_api_gateway_rest_api.htc_private_api.execution_arn}/*"
            ],
            "Condition" : {
                "StringNotEquals": {
                    "aws:SourceVpc": "${var.vpc_id}"
                }
            }
        }
    ]
}
EOF
}
