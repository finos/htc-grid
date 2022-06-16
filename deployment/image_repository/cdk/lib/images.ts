// Copyright 2022 Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


import { Construct } from "constructs";
import * as cdk from "aws-cdk-lib"
import * as ecr from "aws-cdk-lib/aws-ecr";
import * as ecrdeploy from "cdk-ecr-deployment";
import * as fs from "fs" ;
import * as ecr_asset from "aws-cdk-lib/aws-ecr-assets";
import * as path from "path";

interface IEcrPullPushImage {
  repo?: string;
  tag?: string;
  src?: string;
  dest?: string;
}

export class ImagesStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: cdk.StackProps) {
    super(scope, id, props);

    const imagesFileName = this.node.tryGetContext("images");
    const rawImages = fs.readFileSync(imagesFileName, 'utf8')
    const images= JSON.parse(rawImages)
    const keysRepoToCreate = images.repository;
    keysRepoToCreate.forEach((repoName: string) => {
      // Make repo...
      const repo = new ecr.Repository(this, `${repoName}Repo`, {

        repositoryName: repoName,
        //removalPolicy: cdk.RemovalPolicy.DESTROY

      });
    });
    const keysImageToCopy = Object.keys(images.image_to_copy);
    keysImageToCopy.forEach((key,dest) => {
      const srcImage = key;
      const destImage = images.image_to_copy[srcImage]
      // check if image has content to pull + push or not
      const repo = ecr.Repository.fromRepositoryName(this,`ImportECR-${srcImage}`,destImage.split(":")[0])
      this.ecrPullPush(`${srcImage}`, {
        src:srcImage,
        tag:srcImage.split(':').pop(),
        dest:destImage
      }, repo);
    });

    const cfnPullThroughCacheRule = new ecr.CfnPullThroughCacheRule(this, 'MyCfnPullThroughCacheRule', /* all optional props */ {
      ecrRepositoryPrefix: 'ecr-public',
      upstreamRegistryUrl: 'public.ecr.aws',
    });

    const imageProvided = new ecr_asset.DockerImageAsset(this, 'BuildAndPushLambdaProvided', {
      directory: path.join(__dirname, '../../lambda_runtimes'),
      file: "Dockerfile.provided",
      buildArgs : {
        HTCGRID_REGION: props.env?.region || "undefined",
        HTCGRID_ACCOUNT: props.env?.account || "undefined",
      }
    });

    new ecrdeploy.ECRDeployment(this, 'CopyLambdaProvided', {
      src: new ecrdeploy.DockerImageName(imageProvided.imageUri),
      dest: new ecrdeploy.DockerImageName(`${cdk.Stack.of(this).account}.dkr.ecr.${cdk.Stack.of(this).region}.amazonaws.com/lambda:provided`),
    })

    const imagePython3_8 = new ecr_asset.DockerImageAsset(this, 'BuildAndPushLambdaPython3.8', {
      directory: path.join(__dirname, '../../lambda_runtimes'),
      file: "Dockerfile.python3.8",
      buildArgs : {
        HTCGRID_REGION: props.env?.region || "undefined",
        HTCGRID_ACCOUNT: props.env?.account || "undefined",
      }
    });

    new ecrdeploy.ECRDeployment(this, 'CopyLambdaPython3.8', {
      src: new ecrdeploy.DockerImageName(imagePython3_8.imageUri),
      dest: new ecrdeploy.DockerImageName(`${cdk.Stack.of(this).account}.dkr.ecr.${cdk.Stack.of(this).region}.amazonaws.com/lambda:python3.8`),
    });

    const imageDotnet5_0 = new ecr_asset.DockerImageAsset(this, 'BuildAndPushLambdaDotnet5.0', {
      directory: path.join(__dirname, '../../lambda_runtimes'),
      file: "Dockerfile.dotnet5.0",
      buildArgs :  {
        HTCGRID_REGION: props.env?.region || "undefined",
        HTCGRID_ACCOUNT: props.env?.account || "undefined",
      }
    });

    new ecrdeploy.ECRDeployment(this, 'CopyLambdaDotnet5.0', {
      src: new ecrdeploy.DockerImageName(imageDotnet5_0.imageUri),
      dest: new ecrdeploy.DockerImageName(`${cdk.Stack.of(this).account}.dkr.ecr.${cdk.Stack.of(this).region}.amazonaws.com/lambda:python5.0`),
    });

  }

  private ecrPullPush(
    key: string,
    image: IEcrPullPushImage,
    repo: ecr.IRepository
  ) {
    const srcUri = image.src ?? `${image.repo}:${image.tag}`;
    const destUri = `${repo.repositoryUri}:${
      image.dest?.includes(":") ? image.dest!.split(":").pop() : image.tag
    }`;

    new ecrdeploy.ECRDeployment(this, `${key}EcrDeployment`, {
      memoryLimit: 3000,
      src: new ecrdeploy.DockerImageName(srcUri),
      dest: new ecrdeploy.DockerImageName(destUri),
    });
  }
}
