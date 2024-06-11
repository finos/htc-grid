# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


module "ecr_kms_key" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 2.0"

  description             = "CMK KMS Key used to encrypt ECR Repositories"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true

  key_administrators = local.kms_key_admin_arns

  key_statements = [
    {
      sid    = "Allow CMK KMS Key Access via SQS Service"
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
            "ecr.${var.region}.${local.dns_suffix}"
          ]
        }
      ]
    }
  ]

  aliases = ["ecr/htc"]
}


# Create the ECR repositories
resource "aws_ecr_repository" "third_party" {
  for_each = toset(var.repository)

  name         = each.key
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = module.ecr_kms_key.key_arn
  }
}


# Authenticate to ECR
resource "null_resource" "authenticate_to_ecr_repository" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws ecr get-login-password --region ${var.region} | \
      docker login --username AWS --password-stdin ${local.aws_htc_ecr}
    EOT
  }
}


# Create the pull-through cache rules
resource "aws_ecr_pull_through_cache_rule" "ecr-public" {
  ecr_repository_prefix = "ecr-public"
  upstream_registry_url = "public.ecr.aws"
}


resource "aws_ecr_pull_through_cache_rule" "quay" {
  ecr_repository_prefix = "quay"
  upstream_registry_url = "quay.io"
}


resource "aws_ecr_pull_through_cache_rule" "registry_k8s_io" {
  ecr_repository_prefix = "registry-k8s-io"
  upstream_registry_url = "registry.k8s.io"
}


# Destroy ECR Pull Through Cache Repositories
resource "null_resource" "delete_pull_through_cache_repos" {
  for_each = toset(["ecr-public", "quay", "registry-k8s-io"])

  triggers = {
    region = var.region
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      for repo in $(aws ecr describe-repositories --region ${self.triggers.region} | \
        jq -r -c '.repositories[].repositoryName | select(. | contains("${each.key}"))'); do
          aws ecr delete-repository --force --repository-name $repo --region ${self.triggers.region};
        done
    EOT
  }

  depends_on = [
    aws_ecr_pull_through_cache_rule.ecr-public,
    aws_ecr_pull_through_cache_rule.quay,
    aws_ecr_pull_through_cache_rule.registry_k8s_io
  ]
}


#Pull Lambda Build Runtime for local builds
resource "null_resource" "pull_python_env" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = "docker pull --platform linux/amd64 ${local.lambda_build_runtime}"
  }

  depends_on = [
    null_resource.authenticate_to_ecr_repository,
    null_resource.copy_image
  ]
}


# Pull the required images locally, retag and push to ECR
resource "null_resource" "copy_image" {
  for_each = var.image_to_copy

  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      if ! docker pull --platform linux/amd64 ${each.key}
      then
        echo "Failed to download image: ${each.key}. Please check if images_config.json contains the correct source image URI."
        exit 1
      fi
      if ! docker tag ${each.key} $IMAGE_ECR_URI
      then
        echo "Failed to tag ${each.key} to $IMAGE_ECR_URI. Please check if images_config.json contains the correct ECR destination."
        exit 1
      fi
      if ! docker push $IMAGE_ECR_URI
      then
        echo "Failed to push $IMAGE_ECR_URI. Please check if images_config.json contains the correct ECR destination."
        exit 1
      fi
    EOT
    environment = {
      IMAGE_ECR_URI = "${local.aws_htc_ecr}/${split(":", each.value)[0]}:${try(split(":", each.value)[1], split(":", each.key)[1])}"
    }
  }

  depends_on = [
    aws_ecr_repository.third_party,
    null_resource.authenticate_to_ecr_repository
  ]
}
