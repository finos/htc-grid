# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

TAG=mainline
REGION=eu-west-1
GENERATED?=generated
BUCKET_NAME=
FILE_HANDLER=
FUNCTION_HANDLER=
ACCOUNT_ID?=$(shell aws sts get-caller-identity | jq -r '.Account')
BUCKET_NAME=$(shell aws cloudformation describe-stacks --stack-name $(TAG) --region $(REGION) --query 'Stacks[0].Outputs[?OutputKey==`LambdaLayerBucketID`].OutputValue' --output text)
S3_KMS_KEY_ARN=$(shell aws kms describe-key --key-id $(shell aws cloudformation describe-stacks --stack-name $(TAG) --region $(REGION) --query 'Stacks[0].Outputs[?OutputKey==`HTCStateS3KeyAlias`].OutputValue' --output text) --region $(REGION) --query 'KeyMetadata.Arn' --output text)

# EC2 worker backend knobs (override on the command line as needed)
EC2_WORKER_VCPUS?=1
EC2_WORKER_MEMORY_MB?=2048
ORB_MAX_INSTANCES?=5
ORB_TARGET_PENDING_PER_PAIR?=4
ORB_MIN_VCPUS?=0
ORB_MAX_VCPUS?=64
ORB_CONTROL_INTERVAL?=60
ORB_TEMPLATE_ID?=EC2Fleet-Instant-OnDemand


generated-c++: grid_config.json.tpl
	mkdir -p $(GENERATED) && cat grid_config.json.tpl | sed "s|{{region}}|$(REGION)|;s|{{workload_bucket_name}}|$(BUCKET_NAME)|;s|{{workload_bucket_kms_key_arn}}|$(S3_KMS_KEY_ARN)|;s|{{image_tag}}|$(TAG)|;s|{{account_id}}|${ACCOUNT_ID}|" > $(GENERATED)/grid_config.json
	mkdir -p $(GENERATED) && cat full_run_grid_config.json.tpl | sed "s|{{region}}|$(REGION)|;s|{{workload_bucket_name}}|$(BUCKET_NAME)|;s|{{workload_bucket_kms_key_arn}}|$(S3_KMS_KEY_ARN)|;s|{{image_tag}}|$(TAG)|;s|{{account_id}}|${ACCOUNT_ID}|" > $(GENERATED)/full_run_grid_config.json

generated-ec2: ec2_worker_grid_config.json.tpl
	mkdir -p $(GENERATED) && cat ec2_worker_grid_config.json.tpl | sed "s|{{region}}|$(REGION)|;s|{{workload_bucket_name}}|$(BUCKET_NAME)|;s|{{workload_bucket_kms_key_arn}}|$(S3_KMS_KEY_ARN)|;s|{{image_tag}}|$(TAG)|;s|{{account_id}}|${ACCOUNT_ID}|;s|{{ec2_worker_vcpus}}|$(EC2_WORKER_VCPUS)|;s|{{ec2_worker_memory_mb}}|$(EC2_WORKER_MEMORY_MB)|;s|{{orb_max_instances}}|$(ORB_MAX_INSTANCES)|;s|{{orb_target_pending_per_pair}}|$(ORB_TARGET_PENDING_PER_PAIR)|;s|{{orb_min_vcpus}}|$(ORB_MIN_VCPUS)|;s|{{orb_max_vcpus}}|$(ORB_MAX_VCPUS)|;s|{{orb_control_interval}}|$(ORB_CONTROL_INTERVAL)|;s|{{orb_template_id}}|$(ORB_TEMPLATE_ID)|" > $(GENERATED)/grid_config.json

generated-s3-c++: custom_runtime_s3_grid_config.json.tpl
	mkdir -p $(GENERATED) && cat custom_runtime_s3_grid_config.json.tpl | sed "s|{{region}}|$(REGION)|;s|{{workload_bucket_name}}|$(BUCKET_NAME)|;s|{{workload_bucket_kms_key_arn}}|$(S3_KMS_KEY_ARN)|;s|{{image_tag}}|$(TAG)|;s|{{account_id}}|${ACCOUNT_ID}|" > $(GENERATED)/custom_runtime_s3_grid_config.json

generated-python: python_runtime_grid_config.json.tpl
	mkdir -p $(GENERATED) && cat python_runtime_grid_config.json.tpl | sed "s|{{python_file_handler}}|$(FILE_HANDLER)|;s|{{python_function_handler}}|$(FUNCTION_HANDLER)|;s|{{region}}|$(REGION)|;s|{{workload_bucket_name}}|$(BUCKET_NAME)|;s|{{workload_bucket_kms_key_arn}}|$(S3_KMS_KEY_ARN)|;s|{{image_tag}}|$(TAG)|;s|{{account_id}}|${ACCOUNT_ID}|" > $(GENERATED)/python_runtime_grid_config.json

generated-java: java_runtime_grid_config.json.tpl
	mkdir -p $(GENERATED) && cat java_runtime_grid_config.json.tpl | sed "s|{{java_file_handler}}|$(FILE_HANDLER)|;s|{{java_function_handler}}|$(FUNCTION_HANDLER)|;s|{{region}}|$(REGION)|;s|{{workload_bucket_name}}|$(BUCKET_NAME)|;s|{{workload_bucket_kms_key_arn}}|$(S3_KMS_KEY_ARN)|;s|{{image_tag}}|$(TAG)|;s|{{account_id}}|${ACCOUNT_ID}|" > $(GENERATED)/java_runtime_grid_config.json

clean:
	rm -rf $(GENERATED)
