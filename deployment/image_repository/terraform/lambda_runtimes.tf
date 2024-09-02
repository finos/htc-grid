# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


locals {
  # The key represents the tag of the resulting image,
  # while the value is the tag of the source image.
  runtimes_to_build = {
    "provided"  = "provided:al2",
    "python3.8" = "python:3.8",
    "dotnet5.0" = "dotnet:5.0",
    "java17"    = "java:17"
  }
  architecture = "linux/amd64"
}


resource "null_resource" "build_and_push_runtimes" {
  for_each = local.runtimes_to_build

  triggers = {
    aws_htc_ecr       = local.aws_htc_ecr
    lambda_entrypoint = each.key == "provided" ? "lambda_entry_point_provided.sh" : "lambda_entry_point.sh"
    architecture      = local.architecture
    rebuild_runtimes  = var.rebuild_runtimes
    region            = var.region
    always_run        = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      docker build --platform "${self.triggers.architecture}" \
        --build-arg HTCGRID_ECR_REPO="${self.triggers.aws_htc_ecr}/ecr-public/lambda/${each.value}" \
        --build-arg HTCGRID_LAMBDA_ENTRYPOINT="${self.triggers.lambda_entrypoint}" \
        -t "${self.triggers.aws_htc_ecr}/lambda:${each.key}" \
        -f ../lambda_runtimes/Dockerfile ../lambda_runtimes
      docker push ${self.triggers.aws_htc_ecr}/lambda:${each.key}
    EOT
  }

  provisioner "local-exec" {
    when       = destroy
    command    = <<-EOT
      if [ "${self.triggers.rebuild_runtimes}" == "true" ]; then
        docker rmi ${self.triggers.aws_htc_ecr}/lambda:${each.key}
        aws ecr batch-delete-image --repository-name lambda --image-ids imageTag=${each.key} --region ${self.triggers.region}
      fi
    EOT
    on_failure = continue
  }

  depends_on = [
    aws_ecr_repository.third_party,
    null_resource.authenticate_to_ecr_repository
  ]
}
