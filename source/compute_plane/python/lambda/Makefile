# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

SRCS    := $(wildcard */*.py)

test: $(SRCS)
	flake8  --ignore  E131,E501,W503 --statistic --exclude build