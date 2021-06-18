# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name                   = "${var.cluster_name}_cognito_authorizer"
  rest_api_id            = aws_api_gateway_rest_api.htc_grid_public_rest_api.id
  provider_arns          = [ var.cognito_userpool_arn ]
  type = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_rest_api" "htc_grid_public_rest_api" {
  name        = "${var.cluster_name}-public"
  description = "Public API Gateway for HTC Grid"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "htc_grid_public_submit_proxy" {
  path_part   = "submit"
  rest_api_id = aws_api_gateway_rest_api.htc_grid_public_rest_api.id
  parent_id   = aws_api_gateway_rest_api.htc_grid_public_rest_api.root_resource_id
}

resource "aws_api_gateway_integration" "htc_grid_public_submit_proxy_integration" {
  rest_api_id              = aws_api_gateway_rest_api.htc_grid_public_rest_api.id
  resource_id              = aws_api_gateway_resource.htc_grid_public_submit_proxy.id
  http_method              = aws_api_gateway_method.htc_grid_public_submit_proxy_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = module.submit_task.lambda_function_invoke_arn
}


resource "aws_api_gateway_method" "htc_grid_public_submit_proxy_method" {
  rest_api_id                   = aws_api_gateway_rest_api.htc_grid_public_rest_api.id
  resource_id                   = aws_api_gateway_resource.htc_grid_public_submit_proxy.id
  http_method                   = "POST"
  authorization                 = "COGNITO_USER_POOLS"
  authorizer_id                 = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_method_settings" "htc_grid_public_submit_method_setting" {
  rest_api_id = aws_api_gateway_rest_api.htc_grid_public_rest_api.id
  stage_name  = aws_api_gateway_deployment.htc_grid_public_deployment.stage_name
  method_path = "${aws_api_gateway_resource.htc_grid_public_submit_proxy.path_part}/${aws_api_gateway_method.htc_grid_public_submit_proxy_method.http_method}"

  settings {
    metrics_enabled = true
    logging_level   = "INFO"
  }
}



resource "aws_api_gateway_resource" "htc_grid_public_result_proxy" {
  path_part   = "result"
  rest_api_id = aws_api_gateway_rest_api.htc_grid_public_rest_api.id
  parent_id   = aws_api_gateway_rest_api.htc_grid_public_rest_api.root_resource_id
}

resource "aws_api_gateway_integration" "htc_grid_public_result_proxy_integration" {
  rest_api_id              = aws_api_gateway_rest_api.htc_grid_public_rest_api.id
  resource_id              = aws_api_gateway_resource.htc_grid_public_result_proxy.id
  http_method              = aws_api_gateway_method.htc_grid_public_result_proxy_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = module.get_results.lambda_function_invoke_arn
}


resource "aws_api_gateway_method" "htc_grid_public_result_proxy_method" {
  rest_api_id                   = aws_api_gateway_rest_api.htc_grid_public_rest_api.id
  resource_id                   = aws_api_gateway_resource.htc_grid_public_result_proxy.id
  http_method                   = "GET"
  authorization                 = "COGNITO_USER_POOLS"
  authorizer_id                 = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_method_settings" "htc_grid_public_result_method_setting" {
  rest_api_id = aws_api_gateway_rest_api.htc_grid_public_rest_api.id
  stage_name  = aws_api_gateway_deployment.htc_grid_public_deployment.stage_name
  method_path = "${aws_api_gateway_resource.htc_grid_public_result_proxy.path_part}/${aws_api_gateway_method.htc_grid_public_result_proxy_method.http_method}"

  settings {
    metrics_enabled = true
    logging_level   = "INFO"
  }
}


resource "aws_api_gateway_deployment" "htc_grid_public_deployment" {
  depends_on = [aws_api_gateway_method.htc_grid_public_submit_proxy_method,aws_api_gateway_method.htc_grid_public_result_proxy_method]
  rest_api_id = aws_api_gateway_rest_api.htc_grid_public_rest_api.id
  triggers = {
    redeployment = sha1(join(",", tolist([
      jsonencode(aws_api_gateway_integration.htc_grid_public_submit_proxy_integration),
      jsonencode(aws_api_gateway_integration.htc_grid_public_result_proxy_integration),
      jsonencode(aws_api_gateway_integration.htc_grid_public_cancel_proxy_integration)
    ])))
  }

  stage_name = var.api_gateway_version

  lifecycle {
    create_before_destroy = true
  }
}







resource "aws_api_gateway_resource" "htc_grid_public_cancel_proxy" {
  path_part   = "cancel"
  rest_api_id = aws_api_gateway_rest_api.htc_grid_public_rest_api.id
  parent_id   = aws_api_gateway_rest_api.htc_grid_public_rest_api.root_resource_id
}

resource "aws_api_gateway_integration" "htc_grid_public_cancel_proxy_integration" {
  rest_api_id              = aws_api_gateway_rest_api.htc_grid_public_rest_api.id
  resource_id              = aws_api_gateway_resource.htc_grid_public_cancel_proxy.id
  http_method              = aws_api_gateway_method.htc_grid_public_cancel_proxy_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = module.cancel_tasks.lambda_function_invoke_arn
}


resource "aws_api_gateway_method" "htc_grid_public_cancel_proxy_method" {
  rest_api_id                   = aws_api_gateway_rest_api.htc_grid_public_rest_api.id
  resource_id                   = aws_api_gateway_resource.htc_grid_public_cancel_proxy.id
  http_method                   = "POST"
  authorization                 = "COGNITO_USER_POOLS"
  authorizer_id                 = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_method_settings" "htc_grid_public_cancel_method_setting" {
  rest_api_id = aws_api_gateway_rest_api.htc_grid_public_rest_api.id
  stage_name  = aws_api_gateway_deployment.htc_grid_public_deployment.stage_name
  method_path = "${aws_api_gateway_resource.htc_grid_public_cancel_proxy.path_part}/${aws_api_gateway_method.htc_grid_public_cancel_proxy_method.http_method}"

  settings {
    metrics_enabled = true
    logging_level   = "INFO"
  }
}

resource "aws_api_gateway_account" "htc_grid_account" {
  cloudwatch_role_arn = aws_iam_role.cloudwatch.arn
}

resource "aws_lambda_permission" "htc_grid_apigw_lambda_permission_submit" {
  statement_id  = "AllowAPIGatewayInvoke-${local.suffix}"
  action        = "lambda:InvokeFunction"
  function_name = module.submit_task.lambda_function_name
  principal     = "apigateway.amazonaws.com"

  # The "/*/*" portion grants access from any method on any resource
  # within the API Gateway REST API.
  source_arn = "${aws_api_gateway_rest_api.htc_grid_public_rest_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "htc_grid_apigw_lambda_permission_result" {
  statement_id  = "AllowAPIGatewayInvoke-${local.suffix}"
  action        = "lambda:InvokeFunction"
  function_name = module.get_results.lambda_function_name
  principal     = "apigateway.amazonaws.com"

  # The "/*/*" portion grants access from any method on any resource
  # within the API Gateway REST API.
  source_arn = "${aws_api_gateway_rest_api.htc_grid_public_rest_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "htc_grid_apigw_lambda_permission_cancel" {
  statement_id  = "AllowAPIGatewayInvoke-${local.suffix}"
  action        = "lambda:InvokeFunction"
  function_name = module.cancel_tasks.lambda_function_name
  principal     = "apigateway.amazonaws.com"

  # The "/*/*" portion grants access from any method on any resource
  # within the API Gateway REST API.
  source_arn = "${aws_api_gateway_rest_api.htc_grid_public_rest_api.execution_arn}/*/*"
}


resource "aws_iam_role" "cloudwatch" {
  name = "api_gateway_cloudwatch_global-${local.suffix}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "apigateway.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "cloudwatch" {
  name = "default"
  role = aws_iam_role.cloudwatch.id

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams",
                "logs:PutLogEvents",
                "logs:GetLogEvents",
                "logs:FilterLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}