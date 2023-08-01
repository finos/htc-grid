# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

export TAG=mainline
export BUCKET_NAME=$(shell aws cloudformation describe-stacks --stack-name $(TAG) --region $(REGION) --query 'Stacks[0].Outputs[0].OutputValue' --output text)

.PHONY: clean



compile:

	mvn clean package -DincludeScope=runtime


upload: compile

	rm ./lambda -rf
	rm ./lambda.zip -f

	mkdir lambda

	cp -r ./target/classes/com ./lambda
	cp -r ./target/dependency/ ./lambda/lib

	cp -r ./ql/QuantLib.jar ./lambda/lib/
	cp -r ./ql/libQuantLibJNI.so ./lambda/lib/
	cp -r ./ql/libQuantLib.so.0 ./lambda/lib/

	cd ./lambda/ &&  zip -r ./../lambda.zip ./ && cd -
	aws s3 cp lambda.zip s3://$(BUCKET_NAME)

clean:
	rm  lambda.zip
