# HTC-Grid
The high throughput compute grid project (HTC-Grid) is a container based cloud native HPC/Grid environment.
HTC-Grid allows users to submit high volumes of tasks and scale environments dynamically.

### When should I use HTC-Grid ?
HTC-Grid should be used when the following criteria are meet:
1. A high task throughput is required (from 100 to 10,000+ tasks per second).
2. The tasks are loosely coupled.
3. Variable workloads (tasks with heterogeneous execution times) are expected and the solution needs to dynamically scale with the load.
4. The infrastructure needs to be open.

### When should I not use the HTC-Grid ?
HTC-Grid might not be the best choice if :
1. The required task throughput is below 100 tasks per second. Consider [AWS Batch](https://aws.amazon.com/batch/) instead.
2. The tasks are tightly coupled, or use MPI. Consider [AWS Paralell Cluster](https://aws.amazon.com/hpc/parallelcluster/) or [AWS Batch Multi-Node workloads](https://docs.aws.amazon.com/batch/latest/userguide/multi-node-parallel-jobs.html)
3. The tasks used third party licensed software.

### How do I use HTC-Grid ?

The following documentation describes HTC-Grid's system architecture, development guides, troubleshooting in further detail.

* [Architecture](docs/architecture.md)
* [HTC-Grid usage guide](docs/guide.md)
* [API reference](docs/reference.md)
* [HTC-Grid project contribution guide](docs/development.md)


## Getting Started

This section steps through the HTC-Grid's AWS infrastructure and software prerequisites. An AWS account is required along with some limited familiarity of AWS services and terraform. The execution of the [Getting Started](#getting-started) section will create AWS resources not included in the free tier and then will incur cost to your AWS Account. The complete execution of this section will cost at least 50$ per day.

### Local Software Prerequisites

The following resources should be installed upon you local machine (Linux and macOS only are supported).

* docker version > 1.19

* kubectl version > 1.19 (usually installed alongside Docker)

* python 3.7

* [virtualenv](https://pypi.org/project/virtualenv/)

* [aws CLI version 2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)

* [terraform v0.13.4](https://releases.hashicorp.com/terraform/0.13.4/) or [terraform v0.14.9](https://releases.hashicorp.com/terraform/0.14.9/)

* [helm](https://helm.sh/docs/helm/helm_install/) version > 3

* [JQ](https://stedolan.github.io/jq/)



### Installing the HTC-Grid software

Unpack the provided HTC-Grid software ZIP (i.e: `htc-grid-0.1.0.tar.gz`)  or clone the repository into a local directory of your choice; this directory referred to in this documentation as `<project_root>`. Unless stated otherwise, all paths referenced in this documentation are relative to `<project_root>`.

For first time users or windows users, we do recommend the use of Cloud9 as the platform to deploy HTC-Grid. The installation process uses Terraform and also make to build up artifacts and environment. This project provides a CloudFormation Cloud9 Stack that installs all the pre-requisites listed above to deploy and develop HTC-Grid. Just follow the standard process in your account and deploy the **[Cloud9 Cloudformation Stack](/deployment/dev_environment_cloud9/cfn/cloud9-htc-grid.yaml)**. Once the CloudFormation Stack has been created, open either the **Output** section in CloudFormation or go to **Cloud9** in your AWS console and open the newly created Cloud9 environment.

### Configuring Local Environment

#### AWS CLI

Configure the AWS CLI to use your AWS account: see https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html

Check connectivity as follows:

```bash
$ aws sts get-caller-identity
{
    "Account": "XXXXXXXXXXXX",
    "UserId": "XXXXXXXXXXXXXXXXXXXXX",
    "Arn": "arn:aws:iam::XXXXXXXXXXXX:user/XXXXXXX"
}
```

#### Python

The current release of HTC requires python3.7, and the documentation assumes the use of *virtualenv*. Set this up as follows:

```bash
$ cd <project_root>/
$ virtualenv --python=$PATH/python3.7 venv
created virtual environment CPython3.7.10.final.0-64 in 1329ms
  creator CPython3Posix(dest=<project_roor>/venv, clear=False, no_vcs_ignore=False, global=False)
  seeder FromAppData(download=False, pip=bundle, setuptools=bundle, wheel=bundle, via=copy, app_data_dir=/Users/user/Library/Application Support/virtualenv)
    added seed packages: pip==21.0.1, setuptools==54.1.2, wheel==0.36.2
  activators BashActivator,CShellActivator,FishActivator,PowerShellActivator,PythonActivator,XonshActivator

```

Check you have the correct version of python (`3.7.x`), with a path rooted on `<project_root>`, then start the environment:

```
$  source ./venv/bin/activate
(venv) 8c8590cffb8f:htc-grid-0.0.1 $
```

Check the python version as follows:

```bash
$ which python
<project_root>/venv/bin/python
$ python -V
Python 3.7.10
```

For further details on *virtualenv* see https://sourabhbajaj.com/mac-setup/Python/virtualenv.html

### Define variables for deploying the infrastructure
1. To simplify this installation it is suggested that a unique <TAG> name (to be used later) is also used to prefix the different required bucket. TAG needs to follow [S3 naming rules](https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucketnamingrules.html).
   ```bash
      export TAG=<Your tag>
   ```
2. Define the AWS account ID where the grid will be deployed
   ```bash
      export HTCGRID_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
   ```
3. Define the region where the grid will be deployed
   ```bash
      export HTCGRID_REGION=<Your region>
   ```
   `<Your region>` region can be (the list is not exhaustive)
   - `eu-west-1`
   - `eu-west-2`
   - `eu-west-3`
   - `eu-central-1`
   - `us-east-1`
   - `us-west-2`
   - `ap-northeast-1`
   - `ap-southeast-1`

4. In the following section we create a unique UUID to ensure the buckets created are unique, then we create the three environment variables with the S3 bucket names. The S3 buckets will contain:
    * **S3_IMAGE_TFSTATE_HTCGRID_BUCKET_NAME**: The environment variable for the S3 bucket that holds the terraform state to transfer htc-grid docker images to your ECR repository.
    * **S3_TFSTATE_HTCGRID_BUCKET_NAME**: The environment variable for the S3 bucket that holds terraform state for the installation of the htc-grid project
    * **S3_LAMBDA_HTCGRID_BUCKET_NAME**: The environment variable for the S3 bucket that holds the code to be executed when a task is invoked.
   ```bash
   export S3_UUID=$(uuidgen | sed 's/.*-\(.*\)/\1/g'  | tr '[:upper:]' '[:lower:]')
   export S3_IMAGE_TFSTATE_HTCGRID_BUCKET_NAME="${TAG}-image-tfstate-htc-grid-${S3_UUID}"
   export S3_TFSTATE_HTCGRID_BUCKET_NAME="${TAG}-tfstate-htc-grid-${S3_UUID}"
   export S3_LAMBDA_HTCGRID_BUCKET_NAME="${TAG}-lambda-unit-htc-grid-${S3_UUID}"
   ```

### Create the S3 Buckets

1. The following step creates the S3 buckets that will be needed during the installation:

  ```bash
  aws s3 --region $HTCGRID_REGION mb s3://$S3_IMAGE_TFSTATE_HTCGRID_BUCKET_NAME
  aws s3 --region $HTCGRID_REGION mb s3://$S3_TFSTATE_HTCGRID_BUCKET_NAME
  aws s3 --region $HTCGRID_REGION mb s3://$S3_LAMBDA_HTCGRID_BUCKET_NAME
  ```
### Create and deploy HTC-Grid images

The HTC-Grid project has external software dependencies that are deployed as container images. Instead of downloading each time from the public DockerHub repository, this step will pull those dependencies and upload into the your [Amazon Elastic Container Registry (ECR)](https://aws.amazon.com/ecr/).

**Important Note** HTC-Grid uses a few open source project with container images storead at [Dockerhub](https://hub.docker.com/). Dockerhub has a [download rate limit policy](https://docs.docker.com/docker-hub/download-rate-limit/). This may impact you when running this step as an anonymous user as you can get errors when running the terraform command below. To overcome those errors, you can re-run the terraform command and wait until the throttling limit is lifted, or optionally you can create an account in [hub.docker.com](https://hub.docker.com/) and then use the credentials of the account using `docker login` locally to avoid anonymous throttling limitations.


1. As you'll be uploading images to ECR, to avoid timeouts, refresh your ECR authentication token:

   ```bash
   aws ecr get-login-password --region $HTCGRID_REGION | docker login --username AWS --password-stdin $HTCGRID_ACCOUNT_ID.dkr.ecr.$HTCGRID_REGION.amazonaws.com
   ```

2. From the `<project_root>` go to the image repository folder

   ```bash
   cd ./deployment/image_repository/terraform
   ```

3. Now run the command

   ```bash
   terraform init -backend-config="bucket=$S3_IMAGE_TFSTATE_HTCGRID_BUCKET_NAME" \
                  -backend-config="region=$HTCGRID_REGION"
   ```

4. If successful, you can now run *terraform apply* to create the HTC-Grid infrastructure. This can take between 10 and 15 minutes depending on the Internet connection.

    ```bash
    terraform apply -var-file ./images_config.json -var "region=$HTCGRID_REGION" -parallelism=1
    ```

NB: This operation fetches images from external repositories and creates a copy into your ECR account, sometimes the fetch to external repositories may have temporary failures due to the state of the external repositories, If the `terraform apply` fails with errors such as the ones below, re-run the command until `terraform apply` successfully completes.

```bash
name unknown: The repository with name 'xxxxxxxxx' does not exist in the registry with id
```

### Build HTC artifacts

HTC artifacts include: python packages, docker images, configuration files for HTC and k8s. To build and install these:


2. Now build the images for the HTC agent. Return to  `<project_root>`  and run the command:

   ```bash
   make happy-path TAG=$TAG ACCOUNT_ID=$HTCGRID_ACCOUNT_ID REGION=$HTCGRID_REGION BUCKET_NAME=$S3_LAMBDA_HTCGRID_BUCKET_NAME
   ```

   * If `TAG` is omitted then `mainline` will be the chosen has a default value.
   * If `ACCOUNT_ID` is omitted then the value will be resolved by the following command:
    ```bash
    aws sts get-caller-identity --query 'Account' --output text
    ```
   * If `REGION` is omitted then `eu-west-1` will be used.
   * `BUCKET_NAME` refers to the name of the bucket created at the beginning for storing the **HTC-Grid workload lambda function**. This variable is mandatory.

   A folder name `generated` will be created at  `<project_root>`. This folder should contain the following two files:
    * `grid_config.json` a configuration file for the grid with basic setting
    * `single-task-test.yaml`  the kubernetes configuration for running a single tasks on the grid.



### Configuring the HTC-Grid runtime
The `grid_config.json` is ready to deploy, but you can tune it before deployment.
Some important parameters are:
* **region** : the AWS region where all resources are going to be created.
* **grid_storage_service** : the type of storage used for tasks payloads, configurable between [S3 or Redis]
* **eks_worker** : an array describing the autoscaling  group used by EKS


### Deploying HTC-Grid

The deployment time is about 30 min.

1. from the project root
   ```bash
   cd ./deployment/grid/terraform
   ```
2. Run
   ```bash
   terraform init -backend-config="bucket=$S3_TFSTATE_HTCGRID_BUCKET_NAME" \
                   -backend-config="region=$HTCGRID_REGION"
   ```
3. if successful you can run terraform apply to create the infrastructure. HTC-Grid deploys a grafana version behind cognito. The admin password is configurable and should be passed at this stage.
   ```bash
   terraform apply -var-file ../../../generated/grid_config.json -var="grafana_admin_password=<my_grafana_admin_password>"
   ```



### Testing the deployment


1. If `terraform apply` is successful then in the terraform folder two files are  created:

    * `kubeconfig_htc_$TAG`: this file give access to the EKS cluster through kubectl (example: kubeconfig_htc_aws_my_project)
    * `Agent_config.json`: this file contains all the parameters, so the agent can run in the infrastructure

2. Set the connection with the EKS cluster
* If using terraform v0.14.9:
   ```bash
   export KUBECONFIG=$(terraform output -raw kubeconfig)
   ```
* If using terraform v0.13.4:
   ```bash
   export KUBECONFIG=$(terraform output kubeconfig)
   ```

3. Testing the Deployment
    1. Get the number of nodes in the cluster using the command below. Note: You should have one or more nodes. If not please the review the configuration files and particularly the variable `eks_worker`
       ```bash
       kubectl get nodes
       ```

    2. Check is system pods are running using the command below. Note: You should have all pods in running state (this might one minute but no more).

       ```bash
       kubectl -n kube-system get po
       ```

    3. Check if logging and monitoring is deployed using the command below. Note: You should have all pods in running state (this might one minute but no more).

       ```bash
       kubectl -n amazon-cloudwatch get po
       ```

    4. Check if metric server is deployed using the command below. Note: You should have all pods in running state (this might one minute but no more).

       ```bash
       kubectl -n custom-metrics get po
       ```

### Running the example workload
In the folder [mock_computation](./examples/workloads/c++/mock_computation), you will find the code of the C++ program mocking computation. This program can sleep for a given duration or emulate CPU/memory consumption based on the input parameters.
We will use a kubernetes Jobs to submit  one execution of 1 second of this C++ program. The communication between the job and the grid are implemented by a client in folder [./examples/client/python](./examples/client/python).

1. Make sure the connection with the grid is established
   ```bash
   kubectl get nodes
   ```
   if an error is returned, please come back to step 2 of the [previous section](#testing-the-deployment).

2. Change directory to `<project_root>`
3. Run the test:
   ```bash
   kubectl apply -f ./generated/single-task-test.yaml
   ```
3. look at the log of the submission:
   ```bash
   kubectl logs job/single-task -f
   ```
   The test should take about 3 second to execute.
   If you see a successful message without exceptions raised, then the test has been successfully executed.


3. clean the job submission instance:
   ```bash
   kubectl delete -f ./generated/single-task-test.yaml
   ```

### Accessing Grafana
The HTC-Grid project captures metrics into influxdb and exposes those metrics through Grafana. To secure Grafana
we use [Amazon Cognito](https://aws.amazon.com/cognito/). You will need to add a user, using your email, and a password
to access the Grafana landing page.

1. To find out the https endpoint where grafana has been deployed type:

    ```
    kubectl -n grafana get ingress | tail -n 1 | awk '{ print "Grafana URL  -> https://"$4 }'
    ```

    It should output something like:

    ```
    Grafana URL  -> https://k8s-grafana-grafanai-XXXXXXXXXXXX-YYYYYYYYYYY.eu-west-2.elb.amazonaws.com
    ```

    Then take the ADDRESS part and point at that on a browser. **Note**:It will generate a warning as we are using self-signed certificates. Just accept the self-signed certificate to get into grafana

2. Log into the URL. Cognito login screen will come up, use it to sign up with your email and a password.
3. On the AWS Console open Cognito and select the `htc_pool` in the `users_pool` section, then select the `users and groups` and confirm user that you just created. This will allow the user to log in with the credentials you provided in the previous step.
4. Go to the grafana URL above, login and use the credentials that you just signed up with and confirmed. This will take you to the grafana dashboard landing page.
5. Finally, in the landing page for grafana, you can use the user `admin` and the password that you provided in the **Deploying HTC-Grid** section. If you did not provide any password the project sets the default `htcadmin`. We encourage everyone to set a password, even if the grafana dashboard is protected through Cognito.


### Un-Installing and destroying HTC grid
The destruction time is about 15 min.
1. Go in the terraform grid folder `./deployment/grid/terraform`.
2. To remove the grid resources run the following command:
   ```bash
   terraform destroy -var-file ../../../generated/grid_config.json
   ```
3. To remove the images from the ECR repository go to the images folder `deployment/image_repository/terraform` and execute
   ```bash
   terraform destroy -var-file ./images_config.json -var "region=$HTCGRID_REGION"
   ```
4. Finally, this will leave the 3 only resources that you can clean manually, the S3 buckets. You can remove the folders using the following command
   ```bash
   aws s3 --region $HTCGRID_REGION rb --force s3://$S3_IMAGE_TFSTATE_HTCGRID_BUCKET_NAME
   aws s3 --region $HTCGRID_REGION rb --force s3://$S3_TFSTATE_HTCGRID_BUCKET_NAME
   aws s3 --region $HTCGRID_REGION rb --force s3://$S3_LAMBDA_HTCGRID_BUCKET_NAME
   ```

### Build the documentation

1. Go at the root of the git repository
2. run the following command
    ```
    make doc
    ```
    or for deploying the server :
    ```
    make serve
    ```