# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

terraform {
  backend "s3" {
    key    = ".terraform/terraform.tfstate"
    region = "eu-west-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }

  required_version = "~> 1.0"
}


provider "tls" {}

provider "aws" {
  region = var.region
}

provider "archive" {}

# NOTE: kubernetes/helm providers are configured from compute_plane outputs, which is a
# counted module (count=0 when worker_backend="ec2"). The try(...) fallbacks let the providers
# configure to harmless values on the ec2 path, where no kubernetes/helm resource or data source
# is ever instantiated, so the providers are declared-but-never-invoked.
provider "kubernetes" {
  host                   = try(module.compute_plane[0].cluster_endpoint, "https://localhost")
  cluster_ca_certificate = try(base64decode(module.compute_plane[0].certificate_authority), "")

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = [
      "--region",
      var.region,
      "eks",
      "get-token",
      "--cluster-name",
      try(module.compute_plane[0].cluster_name, "none"),
    ]
  }
}

# package manager for kubernetes
provider "helm" {
  helm_driver = "configmap"
  kubernetes {
    host                   = try(module.compute_plane[0].cluster_endpoint, "https://localhost")
    cluster_ca_certificate = try(base64decode(module.compute_plane[0].certificate_authority), "")

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = [
        "--region",
        var.region,
        "eks",
        "get-token",
        "--cluster-name",
        try(module.compute_plane[0].cluster_name, "none"),
      ]
    }
  }
}
