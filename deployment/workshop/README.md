# HTC-Grid Workshop Deployment

This directory contains CloudFormation templates and resources for deploying HTC-Grid workshop environments.

## Workshop CloudFormation Template

The `htc-grid-vscode-workshop.yaml` template creates a complete workshop environment including:

- EC2 instance with VSCode Server
- Pre-installed development tools (AWS CLI, kubectl, Terraform, etc.)
- IAM roles and permissions for HTC-Grid deployment
- Security groups and networking configuration
- Automatic HTC-Grid repository setup

## Deployment

### For AWS Events

Deploy using the provided CloudFormation template at AWS events.

### For Self-Guided Deployment

```bash
# Deploy the workshop stack
aws cloudformation create-stack \
  --stack-name htc-grid-workshop \
  --template-body file://htc-grid-vscode-workshop.yaml \
  --capabilities CAPABILITY_IAM \
  --parameters ParameterKey=ParticipantRoleARN,ParameterValue=arn:aws:iam::ACCOUNT:role/ROLE_NAME

# Get connection details
aws cloudformation describe-stacks \
  --stack-name htc-grid-workshop \
  --query 'Stacks[0].Outputs'
```

## Outputs

The stack provides:
- **VSCodeURL**: HTTPS URL to access VSCode Server
- **VSCodePassword**: Password for VSCode login
- **InstanceId**: EC2 instance identifier

## Pre-installed Tools

The workshop environment includes:
- AWS CLI v2
- kubectl
- Terraform
- Helm
- Python 3.13 with pip and virtualenv
- Docker
- Git
- JQ
- Make

## Usage

1. Deploy the CloudFormation stack
2. Access VSCode using the provided URL and password
3. Follow the [Workshop Setup Guide](../../docs/project/getting_started/workshop-setup.md)
4. Continue with [HTC-Grid Deployment](../../docs/project/getting_started/happy-path.md)

## Cleanup

```bash
# Delete the workshop stack
aws cloudformation delete-stack --stack-name htc-grid-workshop
```

## Support

For workshop-related issues:
- Check the [Troubleshooting Guide](../../docs/project/user_guide/troubleshooting.md)
- Open an issue on [GitHub](https://github.com/finos/htc-grid/issues)
- Contact your workshop facilitator (for AWS events)
