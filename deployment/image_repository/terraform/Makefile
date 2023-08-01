# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

REGION?=eu-west-1

S3_IMAGE_TFSTATE_BUCKET_NAME:=$(shell aws cloudformation describe-stacks --stack-name $(TAG) --region $(REGION) --query 'Stacks[0].Outputs[1].OutputValue' --output text)
TF_SRCS:=$(wildcard *.tf)

all:

.PHONY: clean apply destroy reset


init:
	terraform init -backend-config="bucket=$(S3_IMAGE_TFSTATE_BUCKET_NAME)" -backend-config="region=$(REGION)"

apply: $(TF_SRCS) $(GRID_CONFIG)
	terraform apply -var-file ../images_config.json -parallelism=1 -var region=$(REGION)

destroy:
	terraform destroy -var-file ../images_config.json -var region=$(REGION)

reset:
	rm -rf .terraform

clean:
	rm -rf $(BUILD_DIR)/tag.*