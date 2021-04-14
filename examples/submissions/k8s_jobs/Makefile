# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

SUBMITTER_IMAGE_NAME=submitter
TAG=mainline
ACCOUNT_ID?=$(shell aws sts get-caller-identity | jq -r '.Account')
REGION=eu-west-1
DOCKER_REGISTRY=$(ACCOUNT_ID).dkr.ecr.$(REGION).amazonaws.com
GENERATED?=generated

.PHONY: push push clean generated
all: push generated

build: Dockerfile.Submitter
	docker build ../../.. -t $(DOCKER_REGISTRY)/$(SUBMITTER_IMAGE_NAME):$(TAG) -f ./Dockerfile.Submitter

push: build
	docker push $(DOCKER_REGISTRY)/$(SUBMITTER_IMAGE_NAME):$(TAG)

generated: single-task-test.yaml.tpl
	mkdir -p $(GENERATED) && cat single-task-test.yaml.tpl | sed "s/{{account_id}}/$(ACCOUNT_ID)/;s/{{region}}/$(REGION)/;s/{{image_name}}/$(SUBMITTER_IMAGE_NAME)/;s/{{image_tag}}/$(TAG)/" > $(GENERATED)/single-task-test.yaml

clean:
	rm -rf $(GENERATED)