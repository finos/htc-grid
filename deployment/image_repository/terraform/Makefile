# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

REGION?=eu-west-1

IMAGE_TFSTATE_BUCKET:=$(shell aws cloudformation describe-stacks --stack-name $(TAG) --region $(REGION) --query 'Stacks[0].Outputs[?OutputKey==`ImageTFStateBucketID`].OutputValue' --output text)
S3_KMS_KEY_ARN:=$(shell aws cloudformation describe-stacks --stack-name $(TAG) --region $(REGION) --query 'Stacks[0].Outputs[?OutputKey==`HTCStateS3KeyAlias`].OutputValue' --output text)
TF_SRCS:=$(wildcard *.tf)

all:

.PHONY: clean apply destroy reset


init:
	terraform init -backend-config="bucket=$(IMAGE_TFSTATE_BUCKET)" -backend-config="encrypt=true" -backend-config="kms_key_id=$(S3_KMS_KEY_ARN)" -backend-config="region=$(REGION)"

apply: $(TF_SRCS) $(GRID_CONFIG)
	terraform apply -var-file ../images_config.json -parallelism=1 -var region=$(REGION) -var rebuild_runtimes=$(REBUILD_RUNTIMES)

destroy:
	terraform destroy -var-file ../images_config.json -var region=$(REGION)

#########################################
# execute terraform without confirmation
#########################################
auto-apply: $(TF_SRCS) $(GRID_CONFIG)
	terraform apply -auto-approve -no-color -var-file ../images_config.json -parallelism=1 -var region=$(REGION) -var rebuild_runtimes=$(REBUILD_RUNTIMES)
auto-destroy:
	terraform destroy -auto-approve -no-color -var-file ../images_config.json -var region=$(REGION)
#########################################

reset:
	rm -rf .terraform

clean:
	rm -rf $(BUILD_DIR)/tag.*
