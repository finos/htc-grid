# Prerequisites and Environment Setup

## Python Environment

HTC-Grid requires **Python 3.13** and uses virtualenv for dependency management.

### Setup Virtual Environment

```bash
cd htc-grid
virtualenv -p /usr/bin/python3.13 venv
source ./venv/bin/activate
echo "source ~/environment/htc-grid/venv/bin/activate" >> ~/.bashrc
```

### Validate Python Setup

```bash
which python3
which python
python3 --version
python --version
```

Expected output:
```
~/environment/htc-grid/venv/bin/python3
~/environment/htc-grid/venv/bin/python
Python 3.13.3
Python 3.13.3
```

## Define Environment Variables

Create deployment variables and save them for reuse:

```bash
export TAG=main
export HTCGRID_REGION=$(TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"` \
&& curl -H "X-aws-ec2-metadata-token: $TOKEN" -v 169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region' || "eu-west-1")

# Save variables to file for reuse
for var in TAG HTCGRID_REGION ; do echo "export $var=$(eval "echo \"\$$var\"")" >> load_variables.sh ; done
echo "source ~/environment/htc-grid/load_variables.sh" >> ~/.bashrc

echo -e "Your variables:\n$(cat load_variables.sh)"
```

### Variable Descriptions

- **TAG**: Unique identifier for your HTC-Grid deployment (must follow S3 naming rules)
- **HTCGRID_REGION**: AWS region for deployment

## Required Software

The following tools are required (pre-installed in workshop environments):

* [Docker](https://docs.docker.com/get-docker/) (>= 1.19)
* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) (>= 1.25)
* [Python 3.13](https://www.python.org/downloads/)
* [virtualenv](https://pypi.org/project/virtualenv/)
* [AWS CLI version 2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
* [Helm](https://helm.sh/docs/helm/helm_install/) (>= 3.0)
* [JQ](https://stedolan.github.io/jq/)
* [Terraform](https://releases.hashicorp.com/terraform/1.5.4/) (v1.5.4)

## AWS Permissions Required

Your AWS account/role needs permissions for:

* Create and manage EKS clusters
* Create and manage Lambda functions
* Create and manage DynamoDB tables
* Create and manage SQS queues
* Create and manage S3 buckets
* Create and manage IAM roles and policies
* Create and manage VPC resources
* Create and manage ECR repositories


