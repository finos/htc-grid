# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
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

PACKAGE_DIR := ./dist
PACKAGES    := $(wildcard $(PACKAGE_DIR)/*.whl)
.PHONY: all utils api lambda submitter  packages test test-api test-utils test-agent lambda-init config-c++

all: utils api lambda submitter lambda-init

utils:
	$(MAKE) -C ./source/client/python/utils

install-utils: utils
	pip install --force-reinstall $(PACKAGE_DIR)/utils-*.whl

test-utils:
	$(MAKE) test -C ./source/client/python/utils

api:
	$(MAKE) -C ./source/client/python/api-v0.1

test-api: install-utils
	$(MAKE) test -C ./source/client/python/api-v0.1

test-agent:
	$(MAKE) test -C ./source/compute_plane/python/agent

packages: api utils

test-packages: test-api test-utils

test: test-agent test-packages


lambda: utils api
	$(MAKE) -C ./source/compute_plane/python/agent

lambda-init: utils api
	$(MAKE) -C ./source/compute_plane/shell/attach-layer all

submitter: utils api
	$(MAKE) -C ./examples/submissions/k8s_jobs all

doc: import
	mkdocs build

serve: import
	mkdocs serve

import: packages $(PACKAGES)
	pip install --force-reinstall $(PACKAGES)

upload-c++: config-c++
	$(MAKE) -C ./examples/workloads/c++/mock_computation upload

upload-python: config-python
	$(MAKE) -C ./examples/workloads/python/mock_computation upload

config-c++:
	$(MAKE) -C ./examples/configurations generated-c++

config-python:
	$(MAKE) -C ./examples/configurations generated-python

config-s3-c++:
	$(MAKE) -C ./examples/configurations generated-s3-c++

happy-path: all upload-c++ config-c++

python-happy-path: all upload-python config-python


