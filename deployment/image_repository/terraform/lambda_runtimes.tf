# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

# authenticate to ECR repository
resource "null_resource" "authenticate_to_ecr_public_repository"{
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = " aws ecr-public get-login-password --region us-east-1  | docker login --username AWS --password-stdin public.ecr.aws"
  }
}

#########################################
##### build and push custom runtime #####
#########################################
resource null_resource "build_provided" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = "docker build -t ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/lambda:provided -f ./lambda_runtimes/Dockerfile.provided ./lambda_runtimes"
  }
  depends_on = [
    null_resource.authenticate_to_ecr_public_repository
  ]
}

resource null_resource "push_provided" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = "docker push ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/lambda:provided"
  }
  depends_on = [
    null_resource.authenticate_to_ecr_repository,
    null_resource.build_dotnet50
  ]
}

#########################################
##### build and push python runtime #####
#########################################
resource null_resource "build_provided" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = "docker build -t ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/lambda:python3.8 -f ./lambda_runtimes/Dockerfile.python3.8 ./lambda_runtimes"
  }
  depends_on = [
    null_resource.authenticate_to_ecr_public_repository
  ]
}

resource null_resource "push_provided" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = "docker push ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/lambda:provided"
  }
  depends_on = [
    null_resource.authenticate_to_ecr_repository,
    null_resource.build_dotnet50
  ]
}

#########################################
##### build and push dotnet runtime #####
#########################################
resource null_resource "build_dotnet50" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = "docker build -t ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/lambda:5.0 -f ./lambda_runtimes/Dockerfile.dotnet5.0 ./lambda_runtimes"
  }
  depends_on = [
    null_resource.authenticate_to_ecr_repository
  ]
}

resource null_resource "push_dotnet50" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = "docker push ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/lambda:5.0.2"
  }
  depends_on = [
    null_resource.authenticate_to_ecr_repository,
    null_resource.build_dotnet50
  ]
}
