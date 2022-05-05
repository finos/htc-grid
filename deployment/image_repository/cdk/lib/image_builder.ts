import { Construct } from "constructs";
import * as cdk from "aws-cdk-lib"
import * as ecrdeploy from "cdk-ecr-deployment";
import * as path  from "path";
import * as ecr_asset from "aws-cdk-lib/aws-ecr-assets";



export class ImageBuilderStack extends cdk.Stack {
    constructor(scope: Construct, id: string, props: cdk.StackProps) {
        super(scope, id, props);

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


}
