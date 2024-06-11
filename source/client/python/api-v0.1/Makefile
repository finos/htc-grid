# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

DIST_DIR=../../../../dist
PYTHON_DIST_DIR?=$(DIST_DIR)/python
SRC     := ./api
SRCS    := $(wildcard $(SRC)/*.py)
PACKAGE_NAME=api
PACKAGE_TARGET=$(DIST_DIR)/$(PACKAGE_NAME)-0.1-py3-none-any.whl

.PHONY: all init

all: $(PACKAGE_TARGET)

init:
	pip install --force-reinstall -r requirements.txt

$(PACKAGE_TARGET): setup.py README.md $(SRCS)
	python setup.py bdist_wheel -d $(PYTHON_DIST_DIR)

flake8: $(SRCS) init
	flake8  --ignore  E501,W503,E131,E252 --statistic --exclude build

pytest: $(SRCS) init
	pytest --cov=api ./tests/

test: flake8 pytest
