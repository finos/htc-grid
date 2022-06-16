// Copyright 2022 Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


import { Construct } from "constructs";
import * as cdk from "aws-cdk-lib";
import * as s3 from "aws-cdk-lib/aws-s3";

export class BucketsStack extends cdk.Stack {
  public agentLocation: string;
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const tag = this.node.tryGetContext("tag").toLowerCase();
    const lambdaS3 = new s3.Bucket(this, "lambdaBucket", {
      bucketName: `${tag}-lambda-unit-htc-grid-${this.node.addr}`.substring(
        0,
        63
      ),
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });
    new cdk.CfnOutput(this, "S3_LAMBDA_HTCGRID_BUCKET_NAME", {
      value: lambdaS3.bucketName,
    });
    this.agentLocation = `s3://${lambdaS3.bucketName}/lambda.zip`;
  }
}
