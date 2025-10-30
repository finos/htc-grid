# Happy Path Deployment

This guide provides a complete walkthrough for deploying HTC-Grid from start to finish.

## Installing the HTC-Grid Software

Unpack the provided HTC-Grid software ZIP (e.g., `htc-grid-0.4.0.tar.gz`) or clone the repository:

```bash
git clone https://github.com/finos/htc-grid.git
cd htc-grid
```

!!! tip "VSCode Server Users"
    For first-time or Windows users, we recommend using VSCode Server. Deploy the **[VSCode Server CloudFormation Stack](../../../deployment/workshop/htc-grid-workshop.yaml)** which includes all prerequisites.

## Define Deployment Variables

Set up environment variables for your deployment:

```bash
export TAG=<YourTag>  # Must follow S3 naming rules
export HTCGRID_REGION=<YourRegion>  # e.g., us-east-1, eu-west-1
```

Supported regions include:
- `eu-west-1`, `eu-west-2`, `eu-central-1`
- `us-east-1`, `us-west-2`
- `ap-northeast-1`, `ap-southeast-1`

## Create Infrastructure State Storage

Create S3 buckets for Terraform state and HTC artifacts:

```bash
make init-grid-state TAG=$TAG REGION=$HTCGRID_REGION
```

This creates:
- 2 buckets for Terraform state storage
- 1 bucket for HTC artifacts (Lambda functions)

Validate creation:
```bash
aws cloudformation describe-stacks --stack-name $TAG --region $HTCGRID_REGION --query 'Stacks[0]'
```

## Deploy Container Images to ECR

Pull dependencies and upload to your ECR:

```bash
# Initialize image repository
make init-images TAG=$TAG REGION=$HTCGRID_REGION

# Transfer images (10-15 minutes)
make auto-transfer-images TAG=$TAG REGION=$HTCGRID_REGION
```

!!! warning "Docker Hub Rate Limits"
    If you encounter rate limit errors, create a Docker Hub account and login locally, or retry the command after the throttling period.

Verify ECR repositories:
```bash
aws ecr describe-repositories --query "repositories[*].repositoryUri" --region $HTCGRID_REGION
```

## Deploy HTC-Grid Infrastructure

Initialize and deploy the main infrastructure:

```bash
# Initialize Terraform state
make init-grid-deployment TAG=$TAG REGION=$HTCGRID_REGION

# Deploy HTC-Grid with Grafana password
make auto-apply-custom-runtime TAG=$TAG REGION=$HTCGRID_REGION GRAFANA_ADMIN_PASSWORD=<your_secure_password>
```

!!! info "Grafana Password"
    Choose a secure password following [Cognito Default Policy](https://docs.aws.amazon.com/cognito/latest/developerguide/user-pool-settings-policies.html) requirements.

## Validate Deployment

After successful deployment, validate your setup:

```bash
cd ~/environment/htc-grid/deployment/grid/terraform

# Set agent config for new terminals
export AGENT_CONFIG_FILE=$(terraform output -raw agent_config)
echo "export AGENT_CONFIG_FILE=$AGENT_CONFIG_FILE" >> ~/.bashrc

# Check EKS nodes
kubectl get nodes

# Check HTC-Agent pods
kubectl get pods

# Check all deployments
kubectl get pods --all-namespaces
```

!!! success "Deployment Complete"
    All pods should be in "Running" state. This may take a few minutes to complete.

## Submit Test Tasks

Test your deployment with a simple task:

### Monitor Logs (Optional)

Open additional terminals to monitor components:

```bash
# Terminal 1: HTC-Agent logs
kubectl logs deployment/htc-agent -c agent -f --tail 5

# Terminal 2: Lambda container logs  
kubectl logs deployment/htc-agent -c lambda -f --tail 5
```

### Submit Single Task

```bash
# Deploy test job
kubectl apply -f ~/environment/htc-grid/generated/single-task-test.yaml

# Monitor job logs
kubectl logs job/single-task -f
```

### Verify in DynamoDB

Check task execution in the AWS Console:
1. Go to DynamoDB service
2. Select table `htc_tasks_state_table-<TAG>`
3. Click "Explore Table Items"
4. View your task execution details

### Clean Up Test Job

```bash
kubectl delete -f ~/environment/htc-grid/generated/single-task-test.yaml
```

## Next Steps

- [Submit more complex workloads](../user_guide/creating_your_a_client.md)
- [Monitor your deployment](../user_guide/monitoring.md)
- [Configure priority queues](../user_guide/configuring_priority_queues.md)

!!! warning "Cost Management"
    Remember to clean up resources when not in use to avoid unnecessary charges.

**Important Note:** HTC-Grid uses a few open source project with container images stored at [DockerHub](https://hub.docker.com/). DockerHub has a [download rate limit policy](https://docs.docker.com/docker-hub/download-rate-limit/). This may impact you when running this step as an anonymous user as you can get errors when running the commands below. To overcome those errors, you can re-run the `make transfer-images  TAG=$TAG REGION=$HTCGRID_REGION` command and wait until the throttling limit is lifted, or optionally you can create an account in [hub.docker.com](https://hub.docker.com/) and then use the credentials of the account using `docker login` locally to avoid anonymous throttling limitations.

1. As you'll be uploading images to ECR, to avoid timeouts, refresh your ECR authentication token:
    ```bash
    make ecr-login REGION=$HTCGRID_REGION
    ```

2. The following command will go to the `~/environment/htc-grid/deployment/image_repository/terraform` and initialize the  project:
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

If `make apply-custom-runtime` is successful then in the `deployment/grid/terraform` folder two files are created:

    * `kubeconfig_htc_$TAG`: this file give access to the EKS cluster through kubectl (example: kubeconfig_htc_aws_my_project)
    * `agent_config.json`: this file contains all the parameters, so the agent can run in the infrastructure



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
   aws cognito-idp admin-create-user --user-pool-id $userpoolid --username $USERNAME --temporary-password $PASSWORD --region $HTCGRID_REGION
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
