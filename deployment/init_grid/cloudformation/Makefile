# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


BUILD_DIR:=.build
export TAG
export REGION?=eu-west-1

export IAC_TOOL?=terraform

YAML_SRC:=grid_state_$(IAC_TOOL).yaml

all: $(BUILD_DIR)/grid_init/init-grid-$(TAG)

.PHONY: clean delete init clean-image-state clean-grid-state clean-lambda-storage clean-artifacts

$(BUILD_DIR)/grid_init:
	mkdir -p $(BUILD_DIR)/grid_init

$(BUILD_DIR)/grid_init/tag.$(TAG):
	@touch $(BUILD_DIR)/grid_init/tag.$(TAG)

$(BUILD_DIR)/grid_init/init-grid-$(TAG): $(BUILD_DIR)/grid_init/tag.$(TAG) $(YAML_SRC)
	aws cloudformation create-stack --stack-name $(TAG) --region $(REGION) --template-body file://$(YAML_SRC) --parameters ParameterKey=BucketTag,ParameterValue=$(TAG)
	@echo "Waiting for cloud formation successful deployment"
	@aws cloudformation wait stack-create-complete --stack-name $(TAG) --region $(REGION)
	@touch $(BUILD_DIR)/grid_init/init-grid-$(TAG)
	aws cloudformation describe-stacks --stack-name $(TAG) --region $(REGION) --query 'Stacks[0]'

$(TAG)-workload-bucket: $(BUILD_DIR)/grid_init/init-grid-$(TAG)-workload-bucket

init: $(BUILD_DIR)/grid_init

clean-grid-state:
	aws --region $(REGION) s3 rm --recursive s3://$(shell aws cloudformation describe-stacks --stack-name $(TAG) --region $(REGION) --query 'Stacks[0].Outputs[2].OutputValue' --output text) || true

clean-image-state:
	aws --region $(REGION) s3 rm --recursive s3://$(shell aws cloudformation describe-stacks --stack-name $(TAG) --region $(REGION) --query 'Stacks[0].Outputs[1].OutputValue' --output text) || true

clean-lambda-storage:
	aws --region $(REGION) s3 rm --recursive s3://$(shell aws cloudformation describe-stacks --stack-name $(TAG) --region $(REGION) --query 'Stacks[0].Outputs[0].OutputValue' --output text) || true

clean-terraform: clean-image-state clean-grid-state clean-lambda-storage
clean-cdk: clean-lambda-storage

delete: clean-$(IAC_TOOL)
	aws cloudformation delete-stack --stack-name $(TAG) --region $(REGION)
	aws cloudformation wait stack-delete-complete --stack-name $(shell aws cloudformation describe-stacks --region $(REGION) --stack-name $(TAG) --query 'Stacks[0].StackId' --output text) --region $(REGION)

clean:
	rm -rf $(BUILD_DIR)/grid_init/tag.*
	rm -rf $(BUILD_DIR)/grid_init/init-grid-*
