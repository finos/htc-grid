# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

REGION?=eu-west-1

GRID_TFSTATE_BUCKET:=$(shell aws cloudformation describe-stacks --stack-name $(TAG) --region $(REGION) --query 'Stacks[0].Outputs[?OutputKey==`GridTFStateBucketID`].OutputValue' --output text)
S3_KMS_KEY_ARN:=$(shell aws cloudformation describe-stacks --stack-name $(TAG) --region $(REGION) --query 'Stacks[0].Outputs[?OutputKey==`HTCStateS3KeyAlias`].OutputValue' --output text)
export GRAFANA_ADMIN_PASSWORD?=$(shell uuidgen)
TF_SRCS:=$(wildcard *.tf)

all:

.PHONY: clean apply reset init

#$(BUILD_DIR)/grid:
#	mkdir -p $@

init:
	terraform init -backend-config="bucket=$(GRID_TFSTATE_BUCKET)" -backend-config="encrypt=true" -backend-config="kms_key_id=$(S3_KMS_KEY_ARN)" -backend-config="region=$(REGION)"

# execute terraform with confirmation
#########################################
apply: $(TF_SRCS) $(GRID_CONFIG)
	terraform apply -var-file $(GRID_CONFIG) -var="grafana_admin_password=$(GRAFANA_ADMIN_PASSWORD)"

destroy:
	terraform destroy  -var-file $(GRID_CONFIG)

#########################################
# execute terraform without confirmation
#########################################
auto-apply: $(TF_SRCS) $(GRID_CONFIG)
	terraform apply -auto-approve -no-color -var-file $(GRID_CONFIG) -var="grafana_admin_password=$(GRAFANA_ADMIN_PASSWORD)"
auto-destroy:
	terraform destroy -auto-approve -no-color -var-file $(GRID_CONFIG)
#########################################

reset:
	rm -rf .terraform

get-agent-configuration:
	@terraform output -raw agent_config

get-userpool-id:
	@terraform output -raw user_pool_id

get-client-id:
	@terraform output -raw user_pool_client_id

get-grafana-password:
	@terraform output -raw grafana_admin_password
	@echo

clean:
	rm -rf $(BUILD_DIR)/tag.*
