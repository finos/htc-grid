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

provider "kubernetes" {
  host                   = module.compute_plane.cluster_endpoint
  cluster_ca_certificate = base64decode(module.compute_plane.certificate_authority)

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
      module.compute_plane.cluster_name,
    ]
  }
}

# package manager for kubernetes
provider "helm" {
  helm_driver = "configmap"
  kubernetes {
    host                   = module.compute_plane.cluster_endpoint
    cluster_ca_certificate = base64decode(module.compute_plane.certificate_authority)

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
        module.compute_plane.cluster_name,
      ]
    }
  }
}
