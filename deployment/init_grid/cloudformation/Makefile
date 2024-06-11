# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


BUILD_DIR:=.build
export TAG
export REGION?=eu-west-1
GRID_TFSTATE_BUCKET=$(shell aws cloudformation describe-stacks --stack-name $(TAG) --region $(REGION) --query 'Stacks[0].Outputs[?OutputKey==`GridTFStateBucketID`].OutputValue' --output text || '')
IMAGE_TFSTATE_BUCKET=$(shell aws cloudformation describe-stacks --stack-name $(TAG) --region $(REGION) --query 'Stacks[0].Outputs[?OutputKey==`ImageTFStateBucketID`].OutputValue' --output text || '')
LAMBDA_LAYER_BUCKET=$(shell aws cloudformation describe-stacks --stack-name $(TAG) --region $(REGION) --query 'Stacks[0].Outputs[?OutputKey==`LambdaLayerBucketID`].OutputValue' --output text || '')

YAML_SRC:=grid_state.yaml

all: $(BUILD_DIR)/grid_init/init-grid-$(TAG)

.PHONY: clean delete init clean-image-state clean-grid-state clean-lambda-storage clean-artifacts

$(BUILD_DIR)/grid_init:
	mkdir -p $(BUILD_DIR)/grid_init

$(BUILD_DIR)/grid_init/tag.$(TAG):
	@touch $(BUILD_DIR)/grid_init/tag.$(TAG)

$(BUILD_DIR)/grid_init/init-grid-$(TAG): $(BUILD_DIR)/grid_init/tag.$(TAG) $(YAML_SRC)
	@if [ "$(shell aws cloudformation list-stacks --region $(REGION) --query 'StackSummaries[?StackStatus==`CREATE_COMPLETE` && StackName==`$(TAG)`].StackName' --output text)" != "$(TAG)" ]; then \
	echo "CloudFormation stack $(TAG) doesn't exist. Creating ..."; \
	aws cloudformation create-stack --stack-name $(TAG) --region $(REGION) --template-body file://$(YAML_SRC) --parameters ParameterKey=BucketTag,ParameterValue=$(TAG); else \
	echo "Failed creating the CloudFormation stack as it may already exist. Trying to update ..."; \
	aws cloudformation update-stack --stack-name $(TAG) --region $(REGION) --template-body file://$(YAML_SRC) --parameters ParameterKey=BucketTag,ParameterValue=$(TAG); fi
	@echo "Waiting for the successful deployment of CloudFormation stack $(TAG) ..."
	@aws cloudformation wait stack-create-complete --stack-name $(TAG) --region $(REGION)
	@touch $(BUILD_DIR)/grid_init/init-grid-$(TAG)
	@aws cloudformation describe-stacks --stack-name $(TAG) --region $(REGION) --query 'Stacks[0]'

$(TAG)-workload-bucket: $(BUILD_DIR)/grid_init/init-grid-$(TAG)-workload-bucket

init: $(BUILD_DIR)/grid_init

clean-grid-state:
	../scripts/python/delete_bucket.py $(GRID_TFSTATE_BUCKET)

clean-image-state:
	../scripts/python/delete_bucket.py $(IMAGE_TFSTATE_BUCKET)

clean-lambda-storage:
	../scripts/python/delete_bucket.py $(LAMBDA_LAYER_BUCKET)

clean: clean-image-state clean-grid-state clean-lambda-storage
	rm -rf $(BUILD_DIR)/grid_init/tag.*

delete: clean
	aws cloudformation delete-stack --stack-name $(TAG) --region $(REGION) && \
	aws cloudformation wait stack-delete-complete --stack-name $(shell aws cloudformation describe-stacks --region $(REGION) --stack-name $(TAG) --query 'Stacks[0].StackId' --output text) --region $(REGION) || true
