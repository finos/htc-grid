# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

DIST_DIR=../../../../dist
PYTHON_DIST_DIR?=$(DIST_DIR)/python
SRC     := ./utils
SRCS    := $(wildcard $(SRC)/*.py)
PACKAGE_NAME=utils
PACKAGE_TARGET=$(DIST_DIR)/$(PACKAGE_NAME)-0.1-py3-none-any.whl

.PHONY: all

all: $(PACKAGE_TARGET)

$(PACKAGE_TARGET): setup.py README.md $(SRCS)
	python setup.py bdist_wheel -d $(PYTHON_DIST_DIR)

test: $(SRCS)
	flake8  --ignore  E501,W503 --statistic --exclude build