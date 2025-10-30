# Self-Paced Setup

This guide is for individual deployment in your own AWS account using either VSCode Server or local development environment.

## Option 1: VSCode Server (Recommended)

VSCode Server provides a pre-configured development environment with all necessary tools.

### Deploy VSCode Server Environment

1. **Use the provided CloudFormation template:**
   ```bash
   # Deploy VSCode Server environment
   aws cloudformation create-stack \
     --stack-name htc-grid-vscode \
     --template-url https://raw.githubusercontent.com/finos/htc-grid/main/deployment/workshop/htc-grid-workshop.yaml \
     --capabilities CAPABILITY_IAM
   ```

2. **Access VSCode Server:**
   - Go to CloudFormation in AWS Console
   - Get VSCodeURL and VSCodePassword from stack outputs
   - Open VSCodeURL in browser and login with password

### Setup HTC-Grid Repository

```bash
# Clone the repository
git clone https://github.com/finos/htc-grid.git
cd htc-grid

# Setup Python virtual environment
virtualenv -p /usr/bin/python3.13 venv
source ./venv/bin/activate
echo "source ~/environment/htc-grid/venv/bin/activate" >> ~/.bashrc
```

## Option 2: Local Development

### Prerequisites

Ensure you have the following installed:
- Python 3.13+
- AWS CLI v2
- Terraform >= 1.0
- kubectl
- Docker
- Git

### Setup

1. **Clone repository:**
   ```bash
   git clone https://github.com/finos/htc-grid.git
   cd htc-grid
   ```

2. **Setup Python environment:**
   ```bash
   python3 -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   pip install -r requirements.txt
   ```

3. **Configure AWS credentials:**
   ```bash
   aws configure
   # Or use AWS SSO, environment variables, or IAM roles
   ```

## Validate Setup

```bash
# Check Python version
python --version  # Should show Python 3.13.x

# Validate AWS access
aws sts get-caller-identity

# Check required tools
terraform --version
kubectl version --client
docker --version
```

## Next Steps

Continue with [Prerequisites](./prerequisite.md) to configure your deployment variables and begin the HTC-Grid installation.
