# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

# retrieve the account ID
data "aws_caller_identity" "current" {}

# create all ECR repository
resource "aws_ecr_repository" "third_party" {
  count = length(var.repository)
  name = var.repository[count.index]
}

# authenticate to ECR repository
resource "null_resource" "authenticate_to_ecr_repository"{
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = " aws ecr get-login-password --region ${var.region}  | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
  }
}

# authenticate to ECR repository
resource "null_resource" "authenticate_to_ecr_public_repository"{
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = " aws ecr-public get-login-password --region us-east-1  | docker login --username AWS --password-stdin public.ecr.aws"
  }
}


resource null_resource "pull_python_env" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = "docker pull ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/lambda-build:build-${var.lambda_runtime}"
  }
  depends_on = [
    null_resource.authenticate_to_ecr_repository,
    null_resource.copy_image
  ]
}

# push tag and pull images from every image to copy
resource "null_resource" "copy_image" {
  for_each = var.image_to_copy
  triggers = {
    state = "${each.key}-${each.value}"
  }
  provisioner "local-exec" {
    command = <<-EOT
    if ! docker pull ${each.key}
    then
      echo "cannot download image ${each.key}"
      exit 1
    fi
    if ! docker tag ${each.key} ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${each.value}:${split(":",each.key)[1]}
    then
      echo "cannot tag ${each.key} to ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${each.value}:${split(":",each.key)[1]}"
      exit 1
    fi
    if ! docker push ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${each.value}:${split(":",each.key)[1]}
    then
      echo "echo cannot push ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${each.value}:${split(":",each.key)[1]}"
      exit 1
    fi
  EOT
  }
  depends_on = [
    aws_ecr_repository.third_party,
    null_resource.authenticate_to_ecr_repository,
    null_resource.authenticate_to_ecr_public_repository,
  ]
}
