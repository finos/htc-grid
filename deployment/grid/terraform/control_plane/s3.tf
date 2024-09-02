# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


module "htc_data_bucket_kms_key" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 2.0"

  description             = "CMK to encrypt S3 buckets"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true

  key_administrators = local.kms_key_admin_arns

  key_statements = [
    {
      sid    = "Allow CMK KMS Key Access via S3 Service"
      effect = "Allow"
      actions = [
        "kms:Encrypt*",
        "kms:Decrypt*",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:Describe*"
      ]
      resources = ["*"]

      principals = [
        {
          type        = "AWS"
          identifiers = local.kms_key_admin_arns
        }
      ]

      conditions = [
        {
          test     = "StringEquals"
          variable = "kms:ViaService"
          values = [
            "s3.${var.region}.${local.dns_suffix}"
          ]
        }
      ]
    }
  ]

  aliases = ["s3/${var.cluster_name}"]
}


module "htc_data_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket_prefix = var.s3_bucket
  force_destroy = true

  attach_deny_insecure_transport_policy    = true
  attach_require_latest_tls_policy         = true
  attach_deny_incorrect_encryption_headers = true
  attach_deny_incorrect_kms_key_sse        = true
  attach_deny_unencrypted_object_uploads   = true
  allowed_kms_key_arn                      = module.htc_data_bucket_kms_key.key_arn

  # S3 bucket-level Public Access Block configuration (by default now AWS has made this default as true for S3 bucket-level block public access)
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  # S3 Bucket Ownership Controls
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls
  control_object_ownership = true
  object_ownership         = "BucketOwnerPreferred"

  expected_bucket_owner = local.account_id

  acl = "private" # "acl" conflicts with "grant" and "owner"

  # logging = {
  #   target_bucket = module.log_bucket.s3_bucket_id
  #   target_prefix = "log/"
  # }

  versioning = {
    status     = true
    mfa_delete = false
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        kms_master_key_id = module.htc_data_bucket_kms_key.key_arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  tags = {
    Tag = var.suffix
  }
}
