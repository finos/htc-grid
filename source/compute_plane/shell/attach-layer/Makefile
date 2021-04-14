# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

LAMBDA_INIT_IMAGE_NAME=lambda-init
TAG=mainline
ACCOUNT_ID?=$(shell aws sts get-caller-identity | jq -r '.Account')
REGION=eu-west-1
DOCKER_REGISTRY=$(ACCOUNT_ID).dkr.ecr.$(REGION).amazonaws.com
CONTEXT_DIR=.
LAMBDA_INIT_IMAGE_NAME=lambda-init

.PHONY: all lambda-init  push-lambda-init build-lambda-init

all: lambda-init
lambda-init: build-lambda-init push-lambda-init


build-lambda-init: Dockerfile
	docker build $(CONTEXT_DIR) -t $(DOCKER_REGISTRY)/$(LAMBDA_INIT_IMAGE_NAME):$(TAG) -f ./Dockerfile

push-lambda-init: build-lambda-init
	docker push $(DOCKER_REGISTRY)/$(LAMBDA_INIT_IMAGE_NAME):$(TAG)

