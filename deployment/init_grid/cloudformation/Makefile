# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


BUILD_DIR:=.build
export TAG
export REGION?=eu-west-1

YAML_SRC:=grid_state.yaml

all: $(BUILD_DIR)/grid_init/init-grid-$(TAG)

.PHONY: clean delete init clean-image-state clean-grid-state clean-lambda-storage clean-artifacts

$(BUILD_DIR)/grid_init:
	mkdir -p $(BUILD_DIR)/grid_init

$(BUILD_DIR)/grid_init/tag.$(TAG):
	@touch $(BUILD_DIR)/grid_init/tag.$(TAG)

$(BUILD_DIR)/grid_init/init-grid-$(TAG): $(BUILD_DIR)/grid_init/tag.$(TAG) $(YAML_SRC)
	@if ! aws cloudformation describe-stacks --stack-name $(TAG) --query "Stacks[0].StackName" --output text >/dev/null 2>&1; then \
	aws cloudformation create-stack --stack-name $(TAG) --region $(REGION) --template-body file://$(YAML_SRC) --parameters ParameterKey=BucketTag,ParameterValue=$(TAG); else \
	echo "Failed creating the CloudFormation stack as it may already exist. Trying to update ..."; \
	aws cloudformation update-stack --stack-name $(TAG) --region $(REGION) --template-body file://$(YAML_SRC) --parameters ParameterKey=BucketTag,ParameterValue=$(TAG); fi
	@echo "Waiting for the successful deployment of CloudFormation stack ..."
	@aws cloudformation wait stack-create-complete --stack-name $(TAG) --region $(REGION)
	@touch $(BUILD_DIR)/grid_init/init-grid-$(TAG)
	@aws cloudformation describe-stacks --stack-name $(TAG) --region $(REGION) --query 'Stacks[0]'

$(TAG)-workload-bucket: $(BUILD_DIR)/grid_init/init-grid-$(TAG)-workload-bucket

init: $(BUILD_DIR)/grid_init

clean-grid-state:
	aws --region $(REGION) s3 rm --recursive s3://$(shell aws cloudformation describe-stacks --stack-name $(TAG) --region $(REGION) --query 'Stacks[0].Outputs[?OutputKey==`TfstateHtcGridBucketId`].OutputValue' --output text) || true

clean-image-state:
	aws --region $(REGION) s3 rm --recursive s3://$(shell aws cloudformation describe-stacks --stack-name $(TAG) --region $(REGION) --query 'Stacks[0].Outputs[?OutputKey==`ImageTfstateHtcGridBucketId`].OutputValue' --output text) || true

clean-lambda-storage:
	aws --region $(REGION) s3 rm --recursive s3://$(shell aws cloudformation describe-stacks --stack-name $(TAG) --region $(REGION) --query 'Stacks[0].Outputs[?OutputKey==`LambdaUnitHtcGridBucketId`].OutputValue' --output text) || true

clean: clean-image-state clean-grid-state clean-lambda-storage
	rm -rf $(BUILD_DIR)/grid_init/tag.*

delete: clean
	aws cloudformation delete-stack --stack-name $(TAG) --region $(REGION) && \
	aws cloudformation wait stack-delete-complete --stack-name $(shell aws cloudformation describe-stacks --region $(REGION) --stack-name $(TAG) --query 'Stacks[0].StackId' --output text) --region $(REGION) || true
