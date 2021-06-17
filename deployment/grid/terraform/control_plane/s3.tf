# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/
 
resource "aws_s3_bucket" "htc-stdout-bucket" {
  bucket_prefix = var.s3_bucket
  acl    = "private"
  force_destroy = true
}