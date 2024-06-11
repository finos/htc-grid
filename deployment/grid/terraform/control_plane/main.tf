# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


locals {
  # check if var.suffix is empty then create a random suffix else use var.suffix
  suffix               = var.suffix != "" ? var.suffix : random_string.random.result
  account_id           = data.aws_caller_identity.current.account_id
  dns_suffix           = data.aws_partition.current.dns_suffix
  partition            = data.aws_partition.current.partition
  lambda_build_runtime = "${var.aws_htc_ecr}/ecr-public/sam/build-${var.lambda_runtime}:1"

  default_kms_key_admin_arns = [
    data.aws_caller_identity.current.arn,
    "arn:${local.partition}:iam::${local.account_id}:root"
  ]
  additional_kms_key_admin_role_arns = [for k, v in data.aws_iam_role.additional_kms_key_admin_roles : v.arn]
  kms_key_admin_arns                 = concat(local.default_kms_key_admin_arns, local.additional_kms_key_admin_role_arns)

  sqs_queue_and_dlq_arns = concat(
    [
      for k, v in aws_sqs_queue.htc_task_queue : v.arn
    ],
    [
      for k, v in aws_sqs_queue.htc_task_queue_dlq : v.arn
    ]
  )

  lambda_configuration_s3_bucket = split("/", var.lambda_configuration_s3_source)[2]

  s3_bucket_arns = [
    module.htc_data_bucket.s3_bucket_arn,
    data.aws_s3_bucket.lambda_configuration_s3_source.arn
  ]

  control_plane_kms_key_arns = [
    module.htc_dynamodb_table_kms_key.key_arn,
    module.htc_task_queue_kms_key.key_arn,
    module.htc_task_queue_dlq_kms_key.key_arn,
    module.htc_data_bucket_kms_key.key_arn,
    var.lambda_configuration_s3_source_kms_key_arn
  ]
}


resource "random_string" "random" {
  length  = 10
  special = false
  upper   = false
}
