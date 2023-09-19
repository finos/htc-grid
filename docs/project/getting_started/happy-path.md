# Happy Path


## Installing the HTC-Grid software
Unpack the provided HTC-Grid software ZIP (i.e: `htc-grid-0.4.0.tar.gz`)  or clone the repository into a local directory of your choice; this directory referred in this documentation as `<project_root>`. Unless stated otherwise, all paths referenced in this documentation are relative to `<project_root>`.

For first time users or Windows users, we do recommend the use of Cloud9 as the platform to deploy HTC-Grid. The installation process uses Terraform and also make to build up artifacts and environment. This project provides a CloudFormation Stack that creates a Cloud9 instance with all the prerequisites listed above installed and ready to deploy and develop HTC-Grid. Just follow the standard process in your account and deploy the **[Cloud9 CloudFormation Stack](/deployment/dev_environment_cloud9/cfn/cloud9-htc-grid.yaml)**. Once the CloudFormation Stack has been created, either open the **Output** section in CloudFormation and find the relevant link or go to **Cloud9** in your AWS console from where you can access the newly created Cloud9 environment.


## Define variables for deploying the infrastructure
1. To simplify this installation we suggest that a unique <TAG> name (to be used later) is also used to prefix the different required resources. TAG needs to follow [S3 naming rules](https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucketnamingrules.html).
   ```bash
      export TAG=<YourTag>
   ```
2. Define the region where HTC-Grid will be deployed:
   ```bash
      export HTCGRID_REGION=<YourRegion>
   ```
   `<YourRegion>` can be any AWS Region (the list below is not exhaustive):
    - `eu-west-1`
    - `eu-west-2`
    - `eu-central-1`
    - `us-east-1`
    - `us-west-2`
    - `ap-northeast-1`
    - `ap-southeast-1`


3. Define the infrastructure as code tool used for deployment
   ```bash
   export IAS=<tool>
   ```
   `<tool>` can take two values:
   - `cdk`
   - `terraform`


## Create the infrastructure for storing the state of the HTC Grid
The following step creates 3 S3 buckets that will be needed during the installation:
* 2 buckets will store the state of the different Terraform deployments (if `terraform` based deployment)
* 1 bucket will store the HTC artifacts (the lambda to be executed by the agent)

```bash
make init-grid-state TAG=$TAG REGION=$HTCGRID_REGION
```

To validate the creation of the S3 buckets, you can run

```bash
aws cloudformation describe-stacks --stack-name $TAG --region $HTCGRID_REGION --query 'Stacks[0]'
```

That will list the three S3 Buckets that were just created.


## Create and deploy HTC-Grid images
The HTC-Grid project has external software dependencies that are deployed as container images. Instead of downloading each time from the public DockerHub repository, this step will pull those dependencies and upload into the your [Amazon Elastic Container Registry (ECR)](https://aws.amazon.com/ecr/).

**Important Note:** HTC-Grid uses a few open source project with container images stored at [DockerHub](https://hub.docker.com/). DockerHub has a [download rate limit policy](https://docs.docker.com/docker-hub/download-rate-limit/). This may impact you when running this step as an anonymous user as you can get errors when running the commands below. To overcome those errors, you can re-run the `make transfer-images  TAG=$TAG REGION=$HTCGRID_REGION` command and wait until the throttling limit is lifted, or optionally you can create an account in [hub.docker.com](https://hub.docker.com/) and then use the credentials of the account using `docker login` locally to avoid anonymous throttling limitations.

1. As you'll be uploading images to ECR, to avoid timeouts, refresh your ECR authentication token:
    ```bash
    make ecr-login REGION=$HTCGRID_REGION
    ```

2. The following command will go to the `~/environment/aws-htc-grid/deployment/image_repository/{cdk or terraform}` and initialize the  project:
    ```bash
    make init-images TAG=$TAG REGION=$HTCGRID_REGION
    ```

3. If successful, you can now start the transfer of the images. This can take between 10 and 15 minutes depending on the Internet connection.

    ```bash
    make transfer-images TAG=$TAG REGION=$HTCGRID_REGION
    ```
The following command will list the repositories You can check which repositories have been created in the ECR console or by executing the command :

   ```bash
   aws ecr describe-repositories --region $HTCGRID_REGION --query "repositories[*].repositoryUri"
   ```

NB: This operation fetches images from external repositories and creates a copy into your ECR account, sometimes the fetch to external repositories may have temporary failures due to the state of the external repositories, If the `make transfer-images  TAG=$TAG REGION=$HTCGRID_REGION` fails with errors such as the ones below, re-run the command until `make transfer-images  TAG=$TAG REGION=$HTCGRID_REGION` successfully completes.

```bash
name unknown: The repository with name 'xxxxxxxxx' does not exist in the registry with id
```


## Build HTC artifacts
HTC artifacts include: python packages, docker images, configuration files for HTC and Kubernetes. To build and install these:


1. Now build the images for the HTC agent. Return to `<project_root>` and run the command:

   ```bash
   make happy-path TAG=$TAG REGION=$HTCGRID_REGION
   ```

    * If `TAG` is omitted then `mainline` will be the chosen has a default value.
    * If `REGION` is omitted then `eu-west-1` will be used.
    

   A folder name `generated` will be created at  `<project_root>`. This folder should contain the following two files:
    * `grid_config.json` a configuration file for the grid with basic setting
    * `single-task-test.yaml`  the Kubernetes configuration for running a single tasks on the grid.


## Configuring the HTC-Grid runtime
The `grid_config.json` is ready to deploy, but you can tune it before deployment. Some important parameters are:

   * `region`: the AWS region where all resources are going to be created.
   * `grid_storage_service`: the type of storage used for tasks payloads, configurable between [S3 or Redis]
   * `eks_worker_groups`: an array describing the autoscaling  group used by EKS


## Deploying HTC-Grid
The deployment of HTC-Grid takes about 20 Mins.

1. Initialize state for HTC Grid:
   ```bash
   make init-grid-deployment TAG=$TAG REGION=$HTCGRID_REGION
   ```
2. All the dependencies have been created and are now ready. We are now ready to deploy the HTC-Grid project. There is one last thing to note. HTC-Grid deploys a Grafana version behind [Amazon Cognito](https://aws.amazon.com/cognito/). While you can modify and select which passwords to use in Cognito, the Grafana internal deployment still requires an admin password. Select a memorable password change the value in the placeholder `<my_grafana_admin_password>` below (make this password follows [Cognito default policy](https://docs.aws.amazon.com/cognito/latest/developerguide/user-pool-settings-policies.html)):
   ```bash
   make apply-custom-runtime TAG=$TAG REGION=$HTCGRID_REGION GRAFANA_ADMIN_PASSWORD='<my_grafana_admin_password>'
   ```

For terraform based deployment, if `make apply-custom-runtime` is successful then in the `deployment/grid/terraform` folder two files are created:

    * `kubeconfig_htc_$TAG`: this file give access to the EKS cluster through kubectl (example: kubeconfig_htc_aws_my_project)
    * `Agent_config.json`: this file contains all the parameters, so the agent can run in the infrastructure

For CDK based deployment, if `make apply-custom-runtime` is successful then please run
```bash
$(make get-eks-connection TAG=$TAG REGION=$HTCGRID_REGION)
```


## Testing the deployment
In order to verify our deployment, we can run the following commands:
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


## Running the example workload
In the folder [mock_computation](./examples/workloads/c++/mock_computation), you will find the code of the C++ program mocking computation. This program can sleep for a given duration or emulate CPU/memory consumption based on the input parameters.
We will use a Kubernetes Jobs to submit  one execution of 1 second of this C++ program. The communication between the job and the grid are implemented by a client in folder [./examples/client/python](./examples/client/python).

1. Make sure the connection with HTC-Grid is established:
   ```bash
   kubectl get nodes
   ```
2. Change directory to `<project_root>`
3. Run the test:
   ```bash
   kubectl apply -f ./generated/single-task-test.yaml
   ```
4. look at the log of the submission:
   ```bash
   kubectl logs job/single-task -f
   ```
   The test should take about 3 second to execute.
   If you see a successful message without exceptions raised, then the test has been successfully executed.

5. Clean the job submission instance:
   ```bash
   kubectl delete -f ./generated/single-task-test.yaml
   ```
## Create a Cognito user (CLI)
All the services accessible via a public URL require authentication via Amazon Cognito. In the case of Grafana, a default user called `admin` is created as part of the deployment.
The initial password for the user will be the value for `GRAFANA_ADMIN_PASSWORD`, as used in the section [Deploy HTC-Grid]({{< ref "20_deploy_htc/70_deploying_htc/_index.en.md" >}}). However, you will be required to change this upon your first login.

In addition to the already setup `admin` user, more users can be created as below:

**Warning:**
Replace `<my_cognito_user>` and `<my_cognito_password>` with your own username and password.


1. Choose a Cognito username and password, making sure they follow the [Amazon Cognito Default Policy](https://docs.aws.amazon.com/cognito/latest/developerguide/user-pool-settings-policies.html):
   ```bash
   cd <project_root>
   export USERNAME=<my_cognito_user>
   export PASSWORD=<my_grafana_admin_password>
   ```
2. Get the userpool id:
   ```bash
   userpoolid=$(make get-userpool-id TAG=$TAG REGION=$HTCGRID_REGION)
   ```
3. Create the user
   ```bash
   aws cognito-idp admin-create-user --user-pool-id $userpoolid --username $USERNAME --temporary-password $PASSWORD
   ```

## Accessing Grafana
The HTC-Grid project captures metrics into InfluxDB and exposes those metrics through Grafana. To access Grafana:

1. To find out the HTTPS endpoint where Grafana has been deployed type:
   ```bash
   kubectl -n grafana get ingress | tail -n 1 | awk '{ print "Grafana URL  -> https://"$4 }'
   ```
   It should output something like:
   ```bash
   Grafana URL  -> https://k8s-grafana-grafanai-XXXXXXXXXXXX-YYYYYYYYYYY.eu-west-2.elb.amazonaws.com
   ```
2. Copy the URL and paste that in the address bar of your browser. **Note**: Accessing the website may generate a warning due to the fact that we are using a self-signed certificate. It is safe to just accept the warning and proceed, and you should be redirected to the Cognito sign-in page. 
3. Enter the username and password created in the previous section, and you will be required to change your initial password.
4. If you don't remember or didn't explicitely set your initial Cognito pasword for the Grafana `admin` user, you can retrieve it using the following command:
    ```bash
    make get-grafana-password TAG=$TAG REGION=$HTCGRID_REGION
    ```
5. Once you are signed into Cognito, you will be redirected to Grafana.


## Uninstalling and destroying HTC grid
The destruction time is about 15 min.

1. To remove the grid resources run the following command:
   ```bash
   make destroy-custom-runtime TAG=$TAG REGION=$HTCGRID_REGION
   ```

   1. To remove the images from the ECR repository execute
      1. For cdk based deployment please run the following command:
      ```bash
      image_list="
      node-exporter
      amazonlinux
      k8s-cloudwatch-adapter
      amazon/cloudwatch-agent
      prometheus
      aws-for-fluent-bit
      lambda-build
      kube-state-metrics
      influxdb
      grafana
      k8s-sidecar
      lambda
      configmap-reload
      busybox
      curl
      pushgateway
      amazon/aws-node-termination-handler
      alertmanager
      cluster-autoscaler
      aws-xray-daemon
      awshpc-lambda
      lambda-init
      submitter
      "
      ```

      2. And then
      ```bash
      echo $image_list | tr ' ' '\n'  |  xargs -L1  aws ecr delete-repository --region $HTCGRID_REGION --force --repository-name
      ```

   2. For all deployments
      ```bash
      make destroy-images TAG=$TAG REGION=$HTCGRID_REGION
      ```
3. Finally, we will delete CloudFormation stack which manages the S3 buckets that contain our Terraform state, by running the following command:

**Warning:**
You should leave this step for the very end, once that all the other cleanup processes above have concluded successfully. These buckets contain the state of your Terraform deployments, thus, removing them before destroying the relevant Terraform resources will mean that you will be left with orphaned resources which you will need to clean up manually. 

   ```bash
   make delete-grid-state TAG=$TAG REGION=$HTCGRID_REGION
   ```


## Build the documentation
1. Go at the root of the git repository
2. run the following command
    ```bash
    make doc
    ```
   or for deploying the server :
    ```bash
    make serve
    ```
