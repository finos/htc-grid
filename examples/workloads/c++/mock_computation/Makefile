# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

export TAG=mainline
BUCKET_NAME=$(shell aws cloudformation describe-stacks --stack-name $(TAG) --region $(REGION) --query 'Stacks[0].Outputs[?OutputKey==`LambdaLayerBucketID`].OutputValue' --output text)
S3_KMS_KEY_ARN:=$(shell aws cloudformation describe-stacks --stack-name $(TAG) --region $(REGION) --query 'Stacks[0].Outputs[?OutputKey==`HTCStateS3KeyAlias`].OutputValue' --output text)
HTCGRID_ECR_REPO=$(ACCOUNT_ID).dkr.ecr.$(REGION).amazonaws.com

.PHONY: clean

main: mock_compute_engine.cpp
	g++ mock_compute_engine.cpp -std=c++11 -O3 -o mock_compute_engine

build-env: mock_compute_engine.cpp
	docker build --platform linux/amd64 . -f ./Dockerfile.Build --build-arg HTCGRID_ECR_REPO=$(HTCGRID_ECR_REPO) -t builded-env:$(TAG)

compile: build-env
	docker run --platform linux/amd64 --rm -u $(shell id -u):$(shell id -g) -v $(shell pwd):/app/build builded-env:$(TAG)

upload: compile
	aws s3 cp lambda.zip s3://$(BUCKET_NAME) --region $(REGION) --sse aws:kms --sse-kms-key-id $(S3_KMS_KEY_ARN)

clean:
	rm mock_compute_engine lambda.zip
