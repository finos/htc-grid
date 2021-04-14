# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
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
      version = "~> 3.10"
    }
    null = {
      source = "hashicorp/null"
      version = "~> 3.1.0"
    }
  }
}




provider "aws" {
  region  = var.region
}

provider "null" {
}



