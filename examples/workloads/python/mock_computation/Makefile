# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

export TAG=mainline
export BUCKET_NAME=$(shell aws cloudformation describe-stacks --stack-name $(TAG) --region $(REGION) --query 'Stacks[0].Outputs[0].OutputValue' --output text)

.PHONY: clean


build-env: mock_compute_engine.py
	docker build . -f ./Dockerfile.Build --build-arg HTCGRID_ACCOUNT=$(ACCOUNT_ID) --build-arg HTCGRID_REGION=$(REGION) -t builded-env:$(TAG)

compile: build-env
	docker run --rm -v  $(shell pwd):/app/build  builded-env:$(TAG)

upload: compile
	aws s3 cp lambda.zip s3://$(BUCKET_NAME)

clean:
	rm  lambda.zip
