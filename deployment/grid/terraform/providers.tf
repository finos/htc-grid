# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

terraform {
  backend "s3" {
    key    = ".terraform/terraform.tfstate"
    region = "eu-west-1"
    // encrypt         = true
    // bucket          = "pipelinedeployinglambdasta-terraformstatee9552559-1bd2jx74ma36z"
    // dynamodb_table  = "PipelineDeployingLambdaStack-terraformstatelock0C7DA880-1W6LKAH4MQDDI"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.58.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.15.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.7.1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0.4"
    }
    archive = {
      source = "hashicorp/archive"
      version = "2.2.0"
    }
  }
}


provider "tls" {
}

provider "aws" {
  region  = var.region
}

provider "archive" {
}

provider "kubernetes" {
  host                   = module.compute_plane.cluster_endpoint
  cluster_ca_certificate = base64decode(module.compute_plane.certificate_authority.0.data)
  token                  = module.compute_plane.token
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args        = [
      "--region",
      var.region,
      "eks",
      "get-token",
      "--cluster-name",
      var.cluster_name,
    ]
  }
}

# package manager for kubernetes
provider "helm" {
  helm_driver = "configmap"
  kubernetes {
    host                   = module.compute_plane.cluster_endpoint
    cluster_ca_certificate = base64decode(module.compute_plane.certificate_authority.0.data)
    token                  = module.compute_plane.token
  }
}


