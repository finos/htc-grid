# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

GENERATED?=$(shell pwd)/generated
DIST_DIR?=$(shell pwd)/../../../dist
PYTHON_DIST_DIR?=$(DIST_DIR)/python
DOCKER_USER_ID:=$(shell id -u)
DOCKER_GROUP_ID:=$(shell id -g)
PRIVATE_SRCS    := $(wildcard private/*.yaml)
PUBLIC_SRCS    := $(wildcard public/*.yaml)

PYTHON_PRIVATE_PACKAGE_NAME=privateapi
PYTHON_PUBLIC_PACKAGE_NAME=publicapi
PRIVATE_PACKAGE_TARGET=$(PYTHON_DIST_DIR)/$(PYTHON_PRIVATE_PACKAGE_NAME)-1.0.0-py3-none-any.whl
PUBLIC_PACKAGE_TARGET=$(PYTHON_DIST_DIR)/$(PYTHON_PUBLIC_PACKAGE_NAME)-1.0.0-py3-none-any.whl

.PHONY: all clean

all: install-packages

clean:
	rm -rf $(GENERATED)/python


###########################################################
######## generate directories for python sources ##########
###########################################################
$(GENERATED)/python/private_api:
	mkdir -p $(GENERATED)/python/private_api

$(GENERATED)/python/public_api:
	mkdir -p $(GENERATED)/python/public_api

###########################################
######## generate python sources ##########
###########################################
$(GENERATED)/python/private_api/setup.py: $(PRIVATE_SRCS) $(GENERATED)/python/private_api
	docker run --user "$(DOCKER_USER_ID):$(DOCKER_GROUP_ID)" --rm  --mount "type=bind,src=$(GENERATED)/python/private_api,dst=/tmp/http_api" -v "$(shell pwd)/$(PRIVATE_SRCS):/api.yaml" openapitools/openapi-generator-cli:v6.0.1  generate  -i /api.yaml -g python -o /tmp/http_api  --additional-properties=packageName=$(PYTHON_PRIVATE_PACKAGE_NAME)

$(GENERATED)/python/public_api/setup.py: $(PUBLIC_SRCS) $(GENERATED)/python/public_api
	docker run --user "$(DOCKER_USER_ID):$(DOCKER_GROUP_ID)" --rm  --mount "type=bind,src=$(GENERATED)/python/public_api,dst=/tmp/http_api" -v "$(shell pwd)/$(PUBLIC_SRCS):/api.yaml" openapitools/openapi-generator-cli:v6.0.1 generate   -i /api.yaml -g python -o /tmp/http_api  --additional-properties=packageName=$(PYTHON_PUBLIC_PACKAGE_NAME)


###########################################
####### generate python packages ##########
###########################################
$(PRIVATE_PACKAGE_TARGET): $(GENERATED)/python/private_api/setup.py
	cd $(GENERATED)/python/private_api/ && python setup.py bdist_wheel -d $(PYTHON_DIST_DIR)

$(PUBLIC_PACKAGE_TARGET): $(GENERATED)/python/public_api/setup.py
	cd $(GENERATED)/python/public_api/ && python setup.py bdist_wheel -d $(PYTHON_DIST_DIR)

###########################################
######## install python packages ##########
###########################################
install-private-package: $(PRIVATE_PACKAGE_TARGET)
	pip install --force-reinstall $(PRIVATE_PACKAGE_TARGET)

install-public-package: $(PUBLIC_PACKAGE_TARGET)
	pip install --force-reinstall $(PUBLIC_PACKAGE_TARGET)

install-packages: install-private-package install-public-package
