## Steps to create stacks

- Deploy Steps:
  - Confirm Node version is greater than 14 by running `node -v`. You can install node from [here](https://nodejs.org/en/download/)
  - From this directory (deployment/grid/cdk) run:
  1. `npm install`
  2. `npm update`
  3. set grid deployment tag and region:
     `export TAG=<Your tag>`
     `export HTCGRID_REGION=<Your region>`
     `export HTCGRID_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)`
  4. `cdk bootstrap`
  5. `cdk synth`
  6. `cdk deploy "*ImagesStack" "*BucketsStack"`
  7. Using the output from previous step (BucketsStack.S3LAMBDAHTCGRIDBUCKETNAME = X), set grid bucket location:
     `export S3_LAMBDA_HTCGRID_BUCKET_NAME=<X>`
  8. Build HTC Agent:
  - Return to `<project_root> (cd ../../../)`
  - Setup virtualenv and start it:
    - `virtualenv venv`
    - `source ./venv/bin/activate`
  - Log into ECR `aws ecr get-login-password --region $HTCGRID_REGION | docker login --username AWS --password-stdin $HTCGRID_ACCOUNT_ID.dkr.ecr.$HTCGRID_REGION.amazonaws.com`
  - Run `make happy-path TAG=$TAG REGION=$HTCGRID_REGION BUCKET_NAME=$S3_LAMBDA_HTCGRID_BUCKET_NAME`
  - Deactivate virtualenv `deactivate`
  - Switch back to cdk dir (`cd deployment/grid/cdk`)
  9. Take a look at `cdk.context.json` for grid configurations
  10. `cdk deploy "*HtcAgentStack"`
  - Adding `--require-approval never` to the end of either `cdk deploy` command will deploy without asking for approval per stack

## Useful commands

- `cdk deploy` deploy this stack to your default AWS account/region
- `cdk diff` compare deployed stack with current state
- `cdk synth` emits the synthesized CloudFormation template
