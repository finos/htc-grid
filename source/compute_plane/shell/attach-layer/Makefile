# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

LAMBDA_INIT_IMAGE_NAME=lambda-init
TAG=mainline
ACCOUNT_ID?=$(shell aws sts get-caller-identity | jq -r '.Account')
REGION=eu-west-1
HTCGRID_ECR_REPO=$(ACCOUNT_ID).dkr.ecr.$(REGION).amazonaws.com
CONTEXT_DIR=.
LAMBDA_INIT_IMAGE_NAME=lambda-init

.PHONY: all lambda-init  push-lambda-init build-lambda-init

all: lambda-init
lambda-init: build-lambda-init push-lambda-init


build-lambda-init: Dockerfile
	docker build  --platform linux/amd64 $(CONTEXT_DIR) --build-arg HTCGRID_ECR_REPO=$(HTCGRID_ECR_REPO) --build-arg REGION=$(REGION) -t $(HTCGRID_ECR_REPO)/$(LAMBDA_INIT_IMAGE_NAME):$(TAG) -f ./Dockerfile

push-lambda-init: build-lambda-init
	docker push $(HTCGRID_ECR_REPO)/$(LAMBDA_INIT_IMAGE_NAME):$(TAG)

