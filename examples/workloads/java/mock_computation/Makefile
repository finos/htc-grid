# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

export TAG=mainline
export BUCKET_NAME=$(shell aws cloudformation describe-stacks --stack-name $(TAG) --region $(REGION) --query 'Stacks[0].Outputs[?OutputKey==`LambdaLayerBucketID`].OutputValue' --output text)
S3_KMS_KEY_ARN:=$(shell aws cloudformation describe-stacks --stack-name $(TAG) --region $(REGION) --query 'Stacks[0].Outputs[?OutputKey==`HTCStateS3KeyAlias`].OutputValue' --output text)
HTCGRID_ECR_REPO=$(ACCOUNT_ID).dkr.ecr.$(REGION).amazonaws.com

.PHONY: clean

compile:
	mvn clean package

upload: compile

	rm ./lambda -rf
	rm ./lambda.zip -f

	mkdir lambda

	cp -r ./target/classes/com ./lambda
	cp -r ./target/dependency/ ./lambda/lib

	cd ./lambda/ &&  zip -r ./../lambda.zip ./ && cd -

	aws s3 cp lambda.zip s3://$(BUCKET_NAME) --region $(REGION) --sse aws:kms --sse-kms-key-id $(S3_KMS_KEY_ARN)

clean:
	rm  lambda.zip
