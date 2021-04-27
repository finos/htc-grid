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
      version = "~> 3.37"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.1.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.1.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 3.1.0"
    }
    archive = {
      source = "hashicorp/archive"
      version = "2.1.0"
    }
    template = {
      source = "hashicorp/template"
      version = "2.2.0"
    }
  }
}


provider "template" {
}

provider "tls" {

}

provider "aws" {
  region  = var.region
}

provider "archive" {
}

provider "kubernetes" {
  host                   = module.resources.cluster_endpoint
  cluster_ca_certificate = base64decode(module.resources.certificate_authority.0.data)
  token                  = module.resources.token
}

# package manager for kubernetes
provider "helm" {
  helm_driver = "configmap"
  kubernetes {
    host                   = module.resources.cluster_endpoint
    cluster_ca_certificate = base64decode(module.resources.certificate_authority.0.data)
    token                  = module.resources.token
  }
}


