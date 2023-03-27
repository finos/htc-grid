# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

REGION?=eu-west-1

S3_GRID_TFSTATE_BUCKET_NAME:=$(shell aws cloudformation describe-stacks --stack-name $(TAG) --region $(REGION) --query 'Stacks[0].Outputs[2].OutputValue' --output text)
export GRAFANA_ADMIN_PASSWORD?=$(shell uuidgen)
TF_SRCS:=$(wildcard *.tf)

all:

.PHONY: clean apply reset init

#$(BUILD_DIR)/grid:
#	mkdir -p $@

init:
	terraform init -backend-config="bucket=$(S3_GRID_TFSTATE_BUCKET_NAME)" -backend-config="region=$(REGION)"

# execute terraform with confirmation
#########################################
apply: $(TF_SRCS) $(GRID_CONFIG)
	terraform apply -var-file $(GRID_CONFIG) -var="grafana_admin_password=$(GRAFANA_ADMIN_PASSWORD)" -target module.compute_plane.aws_iam_policy.eks_pull_through_cache_permission -target module.compute_plane.aws_iam_policy.agent_permissions
	terraform apply -var-file $(GRID_CONFIG) -var="grafana_admin_password=$(GRAFANA_ADMIN_PASSWORD)"

destroy:
	terraform destroy  -var-file $(GRID_CONFIG)
#########################################

# execute terraform without confirmation
#########################################
auto-apply: $(TF_SRCS) $(GRID_CONFIG)
	terraform apply -auto-approve -var-file $(GRID_CONFIG) -var="grafana_admin_password=$(GRAFANA_ADMIN_PASSWORD)" -target module.compute_plane.aws_iam_policy.eks_pull_through_cache_permission -target module.compute_plane.aws_iam_policy.agent_permissions
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
	@terraform output grafana_admin_password

clean:
	rm -rf $(BUILD_DIR)/tag.*