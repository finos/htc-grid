# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/



#########################################
##### build and push custom runtime #####
#########################################
resource null_resource "build_provided" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = "docker build --platform linux/amd64 --build-arg HTCGRID_REGION=${var.region} --build-arg HTCGRID_ACCOUNT=${data.aws_caller_identity.current.account_id} -t ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/lambda:provided -f ../lambda_runtimes/Dockerfile.provided ../lambda_runtimes"
  }
  # depends_on = [
  #   null_resource.authenticate_to_ecr_public_repository
  # ]
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
    null_resource.build_provided
  ]
}

#########################################
##### build and push python runtime #####
#########################################
resource null_resource "build_python38" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = "docker build --platform linux/amd64 --build-arg HTCGRID_REGION=${var.region} --build-arg HTCGRID_ACCOUNT=${data.aws_caller_identity.current.account_id} -t ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/lambda:python3.8 -f ../lambda_runtimes/Dockerfile.python3.8 ../lambda_runtimes"
  }
  # depends_on = [
  #   null_resource.authenticate_to_ecr_public_repository
  # ]
}

resource null_resource "push_python38" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = "docker push ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/lambda:python3.8"
  }
  depends_on = [
    null_resource.authenticate_to_ecr_repository,
    null_resource.build_python38
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
    command = "docker build --platform linux/amd64 --build-arg HTCGRID_REGION=${var.region} --build-arg HTCGRID_ACCOUNT=${data.aws_caller_identity.current.account_id} -t ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/lambda:5.0 -f ../lambda_runtimes/Dockerfile.dotnet5.0 ../lambda_runtimes"
  }
  # depends_on = [
  #   null_resource.authenticate_to_ecr_public_repository
  # ]
}

resource null_resource "push_dotnet50" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = "docker push ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/lambda:5.0"
  }
  depends_on = [
    null_resource.authenticate_to_ecr_repository,
    null_resource.build_dotnet50
  ]
}
