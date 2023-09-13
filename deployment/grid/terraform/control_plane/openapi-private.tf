# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


resource "aws_api_gateway_rest_api" "htc_grid_private_rest_api" {
  name = "openapi-${var.cluster_name}-private"

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


resource "aws_api_gateway_deployment" "htc_grid_private_deployment" {
  rest_api_id = aws_api_gateway_rest_api.htc_grid_private_rest_api.id

  triggers = {
    redeployment = templatefile("../../../source/control_plane/openapi/private/api_definition.yaml", {
      region                  = var.region
      account_id              = data.aws_caller_identity.current.account_id
      cancel_lambda_name      = module.cancel_tasks.lambda_function_name
      submit_task_lambda_name = module.submit_task.lambda_function_name
      get_result_lambda_name  = module.get_results.lambda_function_name
    })
  }

  stage_name = var.api_gateway_version

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_rest_api_policy.private_api_policy,
  ]
}


resource "aws_api_gateway_api_key" "htc_grid_api_key" {
  name = var.cluster_name
}


resource "aws_api_gateway_usage_plan" "htc_grid_usage_plan" {
  name = var.cluster_name

  api_stages {
    api_id = aws_api_gateway_rest_api.htc_grid_private_rest_api.id
    stage  = aws_api_gateway_deployment.htc_grid_private_deployment.stage_name
  }
}


resource "aws_api_gateway_usage_plan_key" "htc_grid_usage_plan_key" {
  key_id        = aws_api_gateway_api_key.htc_grid_api_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.htc_grid_usage_plan.id
}


resource "aws_lambda_permission" "openapi_htc_grid_apigw_private_lambda_permission_submit" {
  statement_id  = "AllowPrivateSubmitAPIGatewayInvoke-${local.suffix}"
  action        = "lambda:InvokeFunction"
  function_name = module.submit_task.lambda_function_name
  principal     = "apigateway.amazonaws.com"

  # The "/*/*" portion grants access from any method on any resource
  # within the API Gateway REST API.
  source_arn = "${aws_api_gateway_rest_api.htc_grid_private_rest_api.execution_arn}/*/*"
}


resource "aws_lambda_permission" "openapi_htc_grid_private_apigw_lambda_permission_result" {
  statement_id  = "AllowPrivateResultAPIGatewayInvoke-${local.suffix}"
  action        = "lambda:InvokeFunction"
  function_name = module.get_results.lambda_function_name
  principal     = "apigateway.amazonaws.com"

  # The "/*/*" portion grants access from any method on any resource
  # within the API Gateway REST API.
  source_arn = "${aws_api_gateway_rest_api.htc_grid_private_rest_api.execution_arn}/*/*"
}


resource "aws_lambda_permission" "openapi_htc_grid_apigw_private_lambda_permission_cancel" {
  statement_id  = "AllowPrivateCancelAPIGatewayInvoke-${local.suffix}"
  action        = "lambda:InvokeFunction"
  function_name = module.cancel_tasks.lambda_function_name
  principal     = "apigateway.amazonaws.com"

  # The "/*/*" portion grants access from any method on any resource
  # within the API Gateway REST API.
  source_arn = "${aws_api_gateway_rest_api.htc_grid_private_rest_api.execution_arn}/*/*"
}


resource "aws_api_gateway_rest_api_policy" "private_api_policy" {
  rest_api_id = aws_api_gateway_rest_api.htc_grid_private_rest_api.id

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": "*",
            "Action": "execute-api:Invoke",
            "Resource": [
                "${aws_api_gateway_rest_api.htc_grid_private_rest_api.execution_arn}/*"
            ]
        },
        {
            "Effect": "Deny",
            "Principal": "*",
            "Action": "execute-api:Invoke",
            "Resource": [
                "${aws_api_gateway_rest_api.htc_grid_private_rest_api.execution_arn}/*"
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
