# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

SUBMITTER_IMAGE_NAME=submitter
TAG=mainline
ACCOUNT_ID?=$(shell aws sts get-caller-identity | jq -r '.Account')
REGION=eu-west-1
HTCGRID_ECR_REPO=$(ACCOUNT_ID).dkr.ecr.$(REGION).amazonaws.com
GENERATED?=generated

.PHONY: push push clean generated
all: push generated

build: Dockerfile.Submitter
	docker build --platform linux/amd64 ../../.. --build-arg HTCGRID_ECR_REPO=$(HTCGRID_ECR_REPO) -t $(HTCGRID_ECR_REPO)/$(SUBMITTER_IMAGE_NAME):$(TAG) -f ./Dockerfile.Submitter

push: build
	docker push $(HTCGRID_ECR_REPO)/$(SUBMITTER_IMAGE_NAME):$(TAG)

generated:
	mkdir -p $(GENERATED) && cat single-task-test.yaml.tpl | sed "s/{{account_id}}/$(ACCOUNT_ID)/;s/{{region}}/$(REGION)/;s/{{image_name}}/$(SUBMITTER_IMAGE_NAME)/;s/{{image_tag}}/$(TAG)/" > $(GENERATED)/single-task-test.yaml

	mkdir -p $(GENERATED) && cat batch-task-test.yaml.tpl | sed "s/{{account_id}}/$(ACCOUNT_ID)/;s/{{region}}/$(REGION)/;s/{{image_name}}/$(SUBMITTER_IMAGE_NAME)/;s/{{image_tag}}/$(TAG)/" > $(GENERATED)/batch-task-test.yaml

	mkdir -p $(GENERATED) && cat portfolio-pricing-single-trade.yaml.tpl | sed "s/{{account_id}}/$(ACCOUNT_ID)/;s/{{region}}/$(REGION)/;s/{{image_name}}/$(SUBMITTER_IMAGE_NAME)/;s/{{image_tag}}/$(TAG)/" > $(GENERATED)/portfolio-pricing-single-trade.yaml

	mkdir -p $(GENERATED) && cat portfolio-pricing-book.yaml.tpl | sed "s/{{account_id}}/$(ACCOUNT_ID)/;s/{{region}}/$(REGION)/;s/{{image_name}}/$(SUBMITTER_IMAGE_NAME)/;s/{{image_tag}}/$(TAG)/" > $(GENERATED)/portfolio-pricing-book.yaml

	mkdir -p $(GENERATED) && cat portfolio-pricing-full-run.yaml.tpl | sed "s/{{account_id}}/$(ACCOUNT_ID)/;s/{{region}}/$(REGION)/;s/{{image_name}}/$(SUBMITTER_IMAGE_NAME)/;s/{{image_tag}}/$(TAG)/" > $(GENERATED)/portfolio-pricing-full-run.yaml

	mkdir -p $(GENERATED) && cat cancel-many-small-tasks-test.yaml.tpl | sed "s/{{account_id}}/$(ACCOUNT_ID)/;s/{{region}}/$(REGION)/;s/{{image_name}}/$(SUBMITTER_IMAGE_NAME)/;s/{{image_tag}}/$(TAG)/" > $(GENERATED)/cancel-many-small-tasks-test.yaml

	mkdir -p $(GENERATED) && cat cancel-one-long-task-test.yaml.tpl | sed "s/{{account_id}}/$(ACCOUNT_ID)/;s/{{region}}/$(REGION)/;s/{{image_name}}/$(SUBMITTER_IMAGE_NAME)/;s/{{image_tag}}/$(TAG)/" > $(GENERATED)/cancel-one-long-task-test.yaml

clean:
	rm -rf $(GENERATED)
