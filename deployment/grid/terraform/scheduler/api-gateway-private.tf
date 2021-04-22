# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


resource "aws_api_gateway_rest_api" "htc_grid_private_rest_api" {
  name        = "${var.cluster_name}-private"
  description = "Private API Gateway for HTC Grid"
  endpoint_configuration {
    types = ["PRIVATE"]
  }
  policy = data.aws_iam_policy_document.private_api_policy_document.json
}

resource "aws_api_gateway_resource" "htc_grid_private_submit_proxy" {
  path_part   = "submit"
  rest_api_id = aws_api_gateway_rest_api.htc_grid_private_rest_api.id
  parent_id   = aws_api_gateway_rest_api.htc_grid_private_rest_api.root_resource_id
}

resource "aws_api_gateway_integration" "htc_grid_private_submit_proxy_integration" {
  rest_api_id              = aws_api_gateway_rest_api.htc_grid_private_rest_api.id
  resource_id              = aws_api_gateway_resource.htc_grid_private_submit_proxy.id
  http_method              = aws_api_gateway_method.htc_grid_private_submit_proxy_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = module.submit_task.this_lambda_function_invoke_arn
}


resource "aws_api_gateway_method" "htc_grid_private_submit_proxy_method" {
  rest_api_id                   = aws_api_gateway_rest_api.htc_grid_private_rest_api.id
  resource_id                   = aws_api_gateway_resource.htc_grid_private_submit_proxy.id
  http_method                   = "POST"
  authorization                 = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_method_settings" "htc_grid_private_submit_method_setting" {
  rest_api_id = aws_api_gateway_rest_api.htc_grid_private_rest_api.id
  stage_name  = aws_api_gateway_deployment.htc_grid_private_deployment.stage_name
  method_path = "${aws_api_gateway_resource.htc_grid_private_submit_proxy.path_part}/${aws_api_gateway_method.htc_grid_private_submit_proxy_method.http_method}"

  settings {
    metrics_enabled = true
    logging_level   = "INFO"
  }
}



resource "aws_api_gateway_resource" "htc_grid_private_result_proxy" {
  path_part   = "result"
  rest_api_id = aws_api_gateway_rest_api.htc_grid_private_rest_api.id
  parent_id   = aws_api_gateway_rest_api.htc_grid_private_rest_api.root_resource_id
}

resource "aws_api_gateway_integration" "htc_grid_private_result_proxy_integration" {
  rest_api_id              = aws_api_gateway_rest_api.htc_grid_private_rest_api.id
  resource_id              = aws_api_gateway_resource.htc_grid_private_result_proxy.id
  http_method              = aws_api_gateway_method.htc_grid_private_result_proxy_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = module.get_results.this_lambda_function_invoke_arn
}


resource "aws_api_gateway_method" "htc_grid_private_result_proxy_method" {
  rest_api_id                   = aws_api_gateway_rest_api.htc_grid_private_rest_api.id
  resource_id                   = aws_api_gateway_resource.htc_grid_private_result_proxy.id
  http_method                   = "GET"
  authorization                 = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_method_settings" "htc_grid_private_result_method_setting" {
  rest_api_id = aws_api_gateway_rest_api.htc_grid_private_rest_api.id
  stage_name  = aws_api_gateway_deployment.htc_grid_private_deployment.stage_name
  method_path = "${aws_api_gateway_resource.htc_grid_private_result_proxy.path_part}/${aws_api_gateway_method.htc_grid_private_result_proxy_method.http_method}"

  settings {
    metrics_enabled = true
    logging_level   = "INFO"
  }
}


resource "aws_api_gateway_resource" "htc_grid_private_cancel_proxy" {
  path_part   = "cancel"
  rest_api_id = aws_api_gateway_rest_api.htc_grid_private_rest_api.id
  parent_id   = aws_api_gateway_rest_api.htc_grid_private_rest_api.root_resource_id
}

resource "aws_api_gateway_integration" "htc_grid_private_cancel_proxy_integration" {
  rest_api_id              = aws_api_gateway_rest_api.htc_grid_private_rest_api.id
  resource_id              = aws_api_gateway_resource.htc_grid_private_cancel_proxy.id
  http_method              = aws_api_gateway_method.htc_grid_private_cancel_proxy_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = module.cancel_tasks.this_lambda_function_invoke_arn
}


resource "aws_api_gateway_method" "htc_grid_private_cancel_proxy_method" {
  rest_api_id                   = aws_api_gateway_rest_api.htc_grid_private_rest_api.id
  resource_id                   = aws_api_gateway_resource.htc_grid_private_cancel_proxy.id
  http_method                   = "POST"
  authorization                 = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_method_settings" "htc_grid_private_cancel_method_setting" {
  rest_api_id = aws_api_gateway_rest_api.htc_grid_private_rest_api.id
  stage_name  = aws_api_gateway_deployment.htc_grid_private_deployment.stage_name
  method_path = "${aws_api_gateway_resource.htc_grid_private_cancel_proxy.path_part}/${aws_api_gateway_method.htc_grid_private_cancel_proxy_method.http_method}"

  settings {
    metrics_enabled = true
    logging_level   = "INFO"
  }
}




resource "aws_api_gateway_deployment" "htc_grid_private_deployment" {
  depends_on = [aws_api_gateway_method.htc_grid_private_submit_proxy_method,aws_api_gateway_method.htc_grid_private_result_proxy_method]
  rest_api_id = aws_api_gateway_rest_api.htc_grid_private_rest_api.id
  triggers = {
    redeployment = sha1(join(",", tolist([
    jsonencode(aws_api_gateway_integration.htc_grid_private_submit_proxy_integration),
    jsonencode(aws_api_gateway_integration.htc_grid_private_result_proxy_integration),
    jsonencode(aws_api_gateway_integration.htc_grid_private_cancel_proxy_integration)
    ])))
  }

  stage_name = var.api_gateway_version

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_usage_plan" "htc_grid_usage_plan" {
  name = var.cluster_name

  api_stages {
    api_id = aws_api_gateway_rest_api.htc_grid_private_rest_api.id
    stage  = aws_api_gateway_deployment.htc_grid_private_deployment.stage_name
  }
}

resource "aws_api_gateway_api_key" "htc_grid_api_key" {
  name = var.cluster_name
}

resource "aws_api_gateway_usage_plan_key" "htc_grid_usage_plan_key" {
  key_id        = aws_api_gateway_api_key.htc_grid_api_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.htc_grid_usage_plan.id
}



resource "aws_lambda_permission" "htc_grid_apigw_private_lambda_permission_submit" {
  statement_id  = "AllowPrivateSubmitAPIGatewayInvoke-${local.suffix}"
  action        = "lambda:InvokeFunction"
  function_name = module.submit_task.this_lambda_function_name
  principal     = "apigateway.amazonaws.com"

  # The "/*/*" portion grants access from any method on any resource
  # within the API Gateway REST API.
  source_arn = "${aws_api_gateway_rest_api.htc_grid_private_rest_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "htc_grid_private_apigw_lambda_permission_result" {
  statement_id  = "AllowPrivateResultAPIGatewayInvoke-${local.suffix}"
  action        = "lambda:InvokeFunction"
  function_name = module.get_results.this_lambda_function_name
  principal     = "apigateway.amazonaws.com"

  # The "/*/*" portion grants access from any method on any resource
  # within the API Gateway REST API.
  source_arn = "${aws_api_gateway_rest_api.htc_grid_private_rest_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "htc_grid_apigw_private_lambda_permission_cancel" {
  statement_id  = "AllowPrivateCancelAPIGatewayInvoke-${local.suffix}"
  action        = "lambda:InvokeFunction"
  function_name = module.cancel_tasks.this_lambda_function_name
  principal     = "apigateway.amazonaws.com"

  # The "/*/*" portion grants access from any method on any resource
  # within the API Gateway REST API.
  source_arn = "${aws_api_gateway_rest_api.htc_grid_private_rest_api.execution_arn}/*/*"
}

data "aws_iam_policy_document" "private_api_policy_document" {
  statement {
    effect =  "Allow"
    actions = ["execute-api:Invoke"]
    resources = [
      "execute-api:/*"
    ]
    principals {
      identifiers = ["*"]
      type = "AWS"
    }
  }
  statement {
    effect = "Deny"
    actions = [ "execute-api:Invoke"]
    resources =  [
      "execute-api:/*"
    ]
    condition {
      test = "StringNotEquals"
      values = [ var.vpc_id ]
      variable = "aws:SourceVpc"
    }
    principals {
      identifiers = ["*"]
      type = "AWS"
    }
  }
}

