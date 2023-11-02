# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


module "htc_stdout_bucket_kms_key" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 2.0"

  description             = "CMK to encrypt S3 buckets"
  deletion_window_in_days = 10

  key_administrators = [
    data.aws_caller_identity.current.arn
  ]

  aliases = ["s3/${var.cluster_name}"]
}


resource "aws_s3_bucket" "htc_stdout_bucket" {
  bucket_prefix = var.s3_bucket
  force_destroy = true
}


resource "aws_s3_bucket_versioning" "htc_stdout_bucket" {
  bucket = aws_s3_bucket.htc_stdout_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}


resource "aws_s3_bucket_server_side_encryption_configuration" "htc_stdout_bucket_kms_encryption" {
  bucket = aws_s3_bucket.htc_stdout_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = module.htc_stdout_bucket_kms_key.key_arn
      sse_algorithm     = "aws:kms"
    }
  }
}


resource "aws_s3_bucket_ownership_controls" "htc_stdout_bucket" {
  bucket = aws_s3_bucket.htc_stdout_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}


resource "aws_s3_bucket_acl" "htc_stdout_bucket" {
  bucket = aws_s3_bucket.htc_stdout_bucket.id
  acl    = "private"

  depends_on = [
    aws_s3_bucket_ownership_controls.htc_stdout_bucket,
  ]
}


resource "aws_s3_bucket_public_access_block" "htc_stdout_bucket_public_access_block" {
  bucket = aws_s3_bucket.htc_stdout_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "htc_stdout_bucket_policy_document" {
  statement {
    sid = "HTTPSOnly"
    principals {
      identifiers = ["*"]
      type        = "*"
    }

    actions = [
      "s3:*"
    ]

    effect = "Deny"

    resources = [
      aws_s3_bucket.htc_stdout_bucket.arn,
      "${aws_s3_bucket.htc_stdout_bucket.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}


resource "aws_s3_bucket_policy" "htc_stdout_bucket_policy" {
  bucket = aws_s3_bucket.htc_stdout_bucket.id
  policy = data.aws_iam_policy_document.htc_stdout_bucket_policy_document.json
}
