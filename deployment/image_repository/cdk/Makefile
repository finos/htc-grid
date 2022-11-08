# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

REGION?=eu-west-1



all:

.PHONY: clean apply destroy reset

init:
	npm install && AWS_REGION=$(REGION) cdk bootstrap -c images=../images_config.json

apply: $(TF_SRCS) $(GRID_CONFIG)
	AWS_REGION=$(REGION) cdk deploy -c images=../images_config.json -c region=$(REGION) ImagesStack

destroy:
	AWS_REGION=$(REGION) cdk destroy  -c images=../images_config.json -c region=$(REGION) ImagesStack

reset:
	rm -rf node_modules

clean:
	rm -rf $(BUILD_DIR)/tag.*