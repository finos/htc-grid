#!/usr/bin/env node

// Copyright 2022 Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import {ImagesStack} from "../lib/images";

const app = new cdk.App();

const account =
    process.env.HTCGRID_ACCOUNT_ID ||
    app.account ||
    process.env.CDK_DEFAULT_ACCOUNT;
const region =
    process.env.HTCGRID_REGION || app.node.tryGetContext("region") || app.region;

const env = {
    account: account,
    region: region,
};


new ImagesStack(app, 'ImagesStack', {
  /* If you don't specify 'env', this stack will be environment-agnostic.
   * Account/Region-dependent features and context lookups will not work,
   * but a single synthesized template can be deployed anywhere. */

  /* Uncomment the next line to specialize this stack for the AWS Account
   * and Region that are implied by the current CLI configuration. */
  // env: { account: process.env.CDK_DEFAULT_ACCOUNT, region: process.env.CDK_DEFAULT_REGION },

  /* Uncomment the next line if you know exactly what Account and Region you
   * want to deploy the stack to. */
  // env: { account: '123456789012', region: 'us-east-1' },

  /* For more information, see https://docs.aws.amazon.com/cdk/latest/guide/environments.html */
    env
});
