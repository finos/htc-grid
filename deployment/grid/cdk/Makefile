# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

REGION?=eu-west-1

export GRAFANA_ADMIN_PASSWORD?=$(shell uuidgen)

all:

.PHONY: clean apply reset init

#$(BUILD_DIR)/grid:
#	mkdir -p $@

init:
	npm install && cdk bootstrap -c config=$(GRID_CONFIG)

# execute terraform with confirmation
#########################################
apply: $(TF_SRCS) $(GRID_CONFIG)
	cdk deploy "*HtcAgentStack" -c config=$(GRID_CONFIG) # -var="grafana_admin_password=$(GRAFANA_ADMIN_PASSWORD)"

destroy:
	cdk destroy "*VpcStack" -c config=$(GRID_CONFIG)
#########################################

# execute terraform without confirmation
#########################################
auto-apply: $(TF_SRCS) $(GRID_CONFIG)
	 cdk deploy "*HtcAgentStack" -c config=$(GRID_CONFIG) --require-approval never # -var="grafana_admin_password=$(GRAFANA_ADMIN_PASSWORD)"
auto-destroy:
	cdk destroy "*VpcStack" -c config=$(GRID_CONFIG) --require-approval never
#########################################

reset:
	rm -rf ./node_modules && rm -rf ./cdk.out

get-eks-connection:
	@aws cloudformation describe-stacks --stack-name $(TAG)-EksClusterStack --query 'Stacks[0].Outputs[]| [?contains(to_string(@.OutputKey),`ConfigCommand`) == `true` ]|[0].OutputValue' --output text

get-agent-configuration:
	@terraform output -raw agent_config

get-userpool-id:
	@aws cloudformation describe-stacks --stack-name $TAG-AuthStack --query 'Stacks[0].Outputs[]| [?contains(to_string(@.OutputKey),`Refhtcpool`) == `true` ]|[0].OutputValue' --output text


get-client-id:
	@aws cloudformation describe-stacks --stack-name $TAG-AuthStack --query 'Stacks[0].Outputs[]| [?contains(to_string(@.OutputKey),`Refhtcclient`) == `true` ]|[0].OutputValue' --output text

get-grafana-password:
	@terraform output grafana_admin_password

clean:
	rm -rf $(BUILD_DIR)/tag.* && rm -rf node_modules && rm -rf ./cdk.out


init-grid:
	npm install
	# cdk bootstrap -e
	cdk deploy --exclusively ${TAG}
	
grid-deployment:
	cdk deploy "*HtcAgentStack"