# Workshop Setup (AWS Events)

This guide is for participants attending AWS events or following guided workshops. It uses a pre-configured VSCode Server environment deployed via CloudFormation.

## Deployment Options

### Option 1: AWS Event (Recommended for Events)
If you're attending an AWS hosted event, you'll receive:
- Pre-provisioned AWS account access
- Event-specific setup instructions
- Guided support

### Option 2: Self-Deployed Workshop Environment
Deploy the workshop environment in your own AWS account using the provided CloudFormation template.

## Deploy Workshop CloudFormation Stack

1. **Download the CloudFormation template:**
   ```bash
   wget https://raw.githubusercontent.com/finos/htc-grid/main/deployment/workshop/htc-grid-workshop.yaml
   ```

2. **Deploy via AWS Console:**
   - Go to CloudFormation in your AWS Console
   - Click "Create Stack" → "With new resources"
   - Upload the `htc-grid-workshop.yaml` template
   - Provide a stack name (e.g., `htc-grid-workshop`)
   - Click through to create the stack

3. **Wait for deployment completion** (approximately 10-15 minutes)

## Access Your VSCode Environment

After successful deployment:

1. **Get connection details** from CloudFormation Outputs:
   - **VSCodeURL**: HTTPS URL to access VSCode Server
   - **VSCodePassword**: Password for VSCode login

2. **Login to VSCode:**
   - Open the VSCodeURL in your browser
   - Enter the VSCodePassword when prompted

3. **Validate IAM permissions:**
   ```bash
   # Remove any existing credentials to use instance role
   rm -vf ${HOME}/.aws/credentials
   
   # Validate IAM role
   aws sts get-caller-identity
   ```

   Expected output should contain `VSCodeRole` in the ARN.

## Pre-installed Tools

Your VSCode environment includes:
- AWS CLI (latest)
- kubectl
- Terraform
- Helm
- Python 3.13 with pip and virtualenv
- Git

## Next Steps

Continue with [Prerequisites](./prerequisite.md) to set up your HTC-Grid deployment.

!!! tip "Workshop Support"
    If you encounter issues during an AWS event, ask your workshop facilitator for assistance.
