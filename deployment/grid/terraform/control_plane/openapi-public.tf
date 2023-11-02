# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


resource "aws_api_gateway_rest_api" "htc_public_api" {
  name = "openapi-${var.cluster_name}-public"

  body = jsonencode(yamldecode(templatefile("../../../source/control_plane/openapi/public/api_definition.yaml", {
    region                  = var.region
    account_id              = data.aws_caller_identity.current.account_id
    cancel_lambda_name      = module.cancel_tasks.lambda_function_name
    submit_task_lambda_name = module.submit_task.lambda_function_name
    get_result_lambda_name  = module.get_results.lambda_function_name
    cognito_userpool_arn    = var.cognito_userpool_arn
  })))

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}


resource "aws_api_gateway_deployment" "htc_public_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.htc_public_api.id

  triggers = {
    redeployment = templatefile("../../../source/control_plane/openapi/public/api_definition.yaml", {
      region                  = var.region
      account_id              = data.aws_caller_identity.current.account_id
      cancel_lambda_name      = module.cancel_tasks.lambda_function_name
      submit_task_lambda_name = module.submit_task.lambda_function_name
      get_result_lambda_name  = module.get_results.lambda_function_name
      cognito_userpool_arn    = var.cognito_userpool_arn
    })
  }

  stage_name = var.api_gateway_version

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_lambda_permission" "openapi_htc_apigw_public_lambda_permission_submit" {
  statement_id  = "AllowPublicSubmitAPIGatewayInvoke-${local.suffix}"
  action        = "lambda:InvokeFunction"
  function_name = module.submit_task.lambda_function_name
  principal     = "apigateway.amazonaws.com"

  # The "/*/*" portion grants access from any method on any resource
  # within the API Gateway REST API.
  source_arn = "${aws_api_gateway_rest_api.htc_public_api.execution_arn}/*/*"
}


resource "aws_lambda_permission" "openapi_htc_public_apigw_lambda_permission_result" {
  statement_id  = "AllowPublicResultAPIGatewayInvoke-${local.suffix}"
  action        = "lambda:InvokeFunction"
  function_name = module.get_results.lambda_function_name
  principal     = "apigateway.amazonaws.com"

  # The "/*/*" portion grants access from any method on any resource
  # within the API Gateway REST API.
  source_arn = "${aws_api_gateway_rest_api.htc_public_api.execution_arn}/*/*"
}


resource "aws_lambda_permission" "openapi_htc_apigw_public_lambda_permission_cancel" {
  statement_id  = "AllowPublicCancelAPIGatewayInvoke-${local.suffix}"
  action        = "lambda:InvokeFunction"
  function_name = module.cancel_tasks.lambda_function_name
  principal     = "apigateway.amazonaws.com"

  # The "/*/*" portion grants access from any method on any resource
  # within the API Gateway REST API.
  source_arn = "${aws_api_gateway_rest_api.htc_public_api.execution_arn}/*/*"
}
