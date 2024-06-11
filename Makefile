# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

export TAG=mainline
export ACCOUNT_ID=$(shell aws sts get-caller-identity | jq -r '.Account')
export REGION=eu-west-1
export LAMBDA_INIT_IMAGE_NAME=lambda-init
export LAMBDA_AGENT_IMAGE_NAME=awshpc-lambda
export SUBMITTER_IMAGE_NAME=submitter
export GENERATED=$(shell pwd)/generated
export BUCKET_NAME
export FILE_HANDLER
export FUNCTION_HANDLER
export DIST_DIR=$(shell pwd)/dist
export REBUILD_RUNTIMES
export GRAFANA_ADMIN_PASSWORD
export BUILD_DIR:=(shell pwd)/.build


BUILD_TYPE?=Release

PACKAGE_DIR := ./dist
PYTHON_PACKAGE_DIR := ./dist/python
PACKAGES    := $(wildcard $(PYTHON_PACKAGE_DIR)/*.whl)
.PHONY: all utils api lambda submitter  packages test test-api test-utils test-agent lambda-init config-c++

all: utils api lambda submitter lambda-init k8s-jobs



##################################################
#### Log in to the different docker registry #####
##################################################
ecr-login:
	aws ecr get-login-password --region $(REGION) | docker login --username AWS --password-stdin $(ACCOUNT_ID).dkr.ecr.$(REGION).amazonaws.com

public-ecr-login:
	aws ecr-public get-login-password  --region us-east-1  | docker login --username AWS --password-stdin public.ecr.aws

docker-registry-login: ecr-login public-ecr-login


###############################################
#######     Manage HTC Grid states     ########
###############################################

init-grid-state: ./deployment/init_grid/cloudformation
	$(MAKE) -C $< init
	$(MAKE) -C $<

delete-grid-state: ./deployment/init_grid/cloudformation
	$(MAKE) -C $< delete

clean-grid-state: ./deployment/init_grid/cloudformation
	$(MAKE) -C $< clean


###########################################################################################
#### Manage CDK/Terraform images transfer from third parties to given docker registry  ####
###########################################################################################

init-images : ./deployment/image_repository/terraform
	@$(MAKE) -C $< init

reset-images-deployment: ./deployment/image_repository/terraform
	@$(MAKE) -C $< reset

transfer-images: ./deployment/image_repository/terraform
	@$(MAKE) -C $< apply

auto-transfer-images: ./deployment/image_repository/terraform
	@$(MAKE) -C $< auto-apply

destroy-images: ./deployment/image_repository/terraform
	@$(MAKE) -C $< destroy

auto-destroy-images: ./deployment/image_repository/terraform
	@$(MAKE) -C $< auto-destroy


###############################################
#### Manage HTC Grid Terraform deployment  ####
###############################################
init-grid-deployment: ./deployment/grid/terraform
	@$(MAKE) -C $< GRID_CONFIG=$(GENERATED)/grid_config.json init
reset-grid-deployment: ./deployment/grid/terraform
	@$(MAKE) -C $< GRID_CONFIG=$(GENERATED)/grid_config.json reset


###########################################
##### Custom runtime (C++) with Redis #####
###########################################

# deploy runtime with confirmation
apply-custom-runtime: ./deployment/grid/terraform
	@$(MAKE) -C $< GRID_CONFIG=$(GENERATED)/grid_config.json apply
# deploy runtime without confirmation
auto-apply-custom-runtime: ./deployment/grid/terraform
	@$(MAKE) -C $< GRID_CONFIG=$(GENERATED)/grid_config.json auto-apply
# destroy runtime with confirmation
destroy-custom-runtime: ./deployment/grid/terraform
	@$(MAKE) -C $< GRID_CONFIG=$(GENERATED)/grid_config.json destroy
# destroy runtime without confirmation
auto-destroy-custom-runtime: ./deployment/grid/terraform
	@$(MAKE) -C $< GRID_CONFIG=$(GENERATED)/grid_config.json auto-destroy


########################################
##### Custom runtime (C++) with S3 #####
########################################

# deploy runtime with confirmation
apply-custom-runtime-s3: ./deployment/grid/terraform
	@$(MAKE) -C $< ./deployment/grid/terraform GRID_CONFIG=$(GENERATED)/custom_runtime_s3_grid_config.json apply
# deploy runtime without confirmation
auto-apply-custom-runtime-s3: ./deployment/grid/terraform
	@$(MAKE) -C $< GRID_CONFIG=$(GENERATED)/custom_runtime_s3_grid_config.json auto-apply
# destroy runtime with confirmation
destroy-custom-runtime-s3: ./deployment/grid/terraform
	@$(MAKE) -C $< GRID_CONFIG=$(GENERATED)/custom_runtime_s3_grid_config.json destroy
# destroy runtime without confirmation
auto-destroy-custom-runtime-s3: ./deployment/grid/terraform
	@$(MAKE) -C $< GRID_CONFIG=$(GENERATED)/custom_runtime_s3_grid_config.json auto-destroy


##################################################
##### Python runtime targets (Python, Redis) #####
##################################################

# deploy runtime with confirmation
apply-python-runtime: ./deployment/grid/terraform
	@$(MAKE) -C $< GRID_CONFIG=$(GENERATED)/python_runtime_grid_config.json apply
# deploy runtime without confirmation
auto-apply-python-runtime: ./deployment/grid/terraform
	@$(MAKE) -C $< GRID_CONFIG=$(GENERATED)/python_runtime_grid_config.json auto-apply
# destroy runtime with confirmation
destroy-python-runtime: ./deployment/grid/terraform
	@$(MAKE) -C $<  GRID_CONFIG=$(GENERATED)/python_runtime_grid_config.json destroy
# destroy runtime without confirmation
auto-destroy-python-runtime: ./deployment/grid/terraform
	@$(MAKE) -C $< GRID_CONFIG=$(GENERATED)/python_runtime_grid_config.json auto-destroy


##########################################################
#### Retrieve output value from terraform deployment #####
##########################################################

get-grafana-password: ./deployment/grid/terraform
	@$(MAKE) --no-print-directory -C $< get-grafana-password

get-userpool-id: ./deployment/grid/terraform
	@$(MAKE) --no-print-directory -C $< get-userpool-id

get-client-id: ./deployment/grid/terraform
	@$(MAKE) --no-print-directory -C $< get-client-id

get-agent-configuration: ./deployment/grid/terraform
	@$(MAKE) --no-print-directory -C $< get-agent-configuration


#############################
##### Building source #######
#############################
http-apis:
	$(MAKE) -C ./source/control_plane/openapi/ all

utils:
	$(MAKE) -C ./source/client/python/utils

install-utils: utils
	pip install --force-reinstall $(PYTHON_PACKAGE_DIR)/utils-*.whl

test-utils:
	$(MAKE) test -C ./source/client/python/utils

api: http-apis
	$(MAKE) -C ./source/client/python/api-v0.1

test-api: install-utils
	$(MAKE) test -C ./source/client/python/api-v0.1

test-agent:
	$(MAKE) test -C ./source/compute_plane/python/agent

packages: api utils

test-packages: test-api test-utils

test: test-agent test-packages


#############################
##### Building images #######
#############################
lambda: utils api
	$(MAKE) -C ./source/compute_plane/python/agent

lambda-init: utils api
	$(MAKE) -C ./source/compute_plane/shell/attach-layer all

python-submitter: utils api
	$(MAKE) -C ./examples/client/python


####################################
##### Building documentation #######
####################################
doc: import
	mkdocs build

serve: import
	mkdocs serve

import: packages $(PACKAGES)
	pip install --force-reinstall $(PACKAGES)


######################################
##### Upload workload binaries #######
######################################
upload-c++: config-c++
	$(MAKE) -C ./examples/workloads/c++/mock_computation upload

upload-python: config-python
	$(MAKE) -C ./examples/workloads/python/mock_computation upload

upload-python-ql: config-python
	$(MAKE) -C ./examples/workloads/python/quant_lib upload

config-c++:
	@$(MAKE) -C ./examples/configurations generated-c++

config-python:
	@$(MAKE) -C ./examples/configurations generated-python FILE_HANDLER="mock_compute_engine.lambda_handler" FUNCTION_HANDLER=lambda_handler

config-python-ql:
	@$(MAKE) -C ./examples/configurations generated-python FILE_HANDLER="portfolio_pricing_engine.lambda_handler" FUNCTION_HANDLER=lambda_handler

config-s3-c++:
	@$(MAKE) -C ./examples/configurations generated-s3-c++


###############################
##### Generate k8s jobs #######
###############################
k8s-jobs:
	@$(MAKE) -C ./examples/submissions/k8s_jobs


#############################
##### Path per example ######
#############################
happy-path: ecr-login all upload-c++ config-c++

python-happy-path: ecr-login all upload-python config-python

python-quant-lib-path: ecr-login all upload-python-ql config-python-ql
