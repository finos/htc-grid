# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/
 
locals {
  # check if var.suffix is empty then create a random suffix else use var.suffix
  suffix = var.suffix != "" ? var.suffix : random_string.random.result
}

resource "random_string" "random" {
  length = 5
  special = false
}
