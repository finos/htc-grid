# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


locals {
  # check if var.suffix is empty then create a random suffix else use var.suffix
  suffix  = var.suffix != "" ? var.suffix : random_string.random.result
  handler = var.lambda_handler_file_name == "" ? "${var.lambda_handler_file_name}.${var.lambda_handler_function_name}" : var.lambda_handler_file_name
}


resource "random_string" "random" {
  length  = 10
  special = false
  upper   = false
  # number = false
}
