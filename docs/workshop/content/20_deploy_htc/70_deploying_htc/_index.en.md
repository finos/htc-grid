---
title: "Deploying HTC-Grid"
chapter: false
weight: 80
---

We are now ready to deploy HTC-Grid using the terraform stack provided by the project. The terraform stack uses `~/environment/aws-htc-grid/generated/grid_config.json` to drive the configuration of the deployment.

Before we deploy the project, we need to initialize the terraform state. Remember we will be using the `$S3_TFSTATE_HTCGRID_BUCKET_NAME` bucket to hold the state. You can read more about the S3 terraform backend [here](https://www.terraform.io/docs/language/settings/backends/s3.html).

```
make init-grid-deployment TAG=$TAG REGION=$HTCGRID_REGION
```

All the dependencies have been created and are now ready. We are now ready to deploy the HTC-Grid project. There is one last thing to note. HTC-Grid deploys Grafana running inside EKS which is authenticated using [Amazon Cognito](https://aws.amazon.com/cognito/). While you can modify and select which passwords to use in Amazon Cognito, the Grafana internal deployment still requires an `admin` password. Select a memorable password and use the value instead of the placeholder `<my_grafana_admin_password>` below (make sure this password follows the [Cognito Default Policy](https://docs.aws.amazon.com/cognito/latest/developerguide/user-pool-settings-policies.html)):

```
make apply-custom-runtime TAG=$TAG REGION=$HTCGRID_REGION GRAFANA_ADMIN_PASSWORD='<my_grafana_admin_password>'
```

{{% notice note %}}
The execution of this command will prompt for `yes` to continue. Just type `yes` and click Enter for the command to proceed.
{{% /notice %}}

{{% notice warning %}}
The installation may take ~20mins. If the `terraform apply` fails with the following error, then it will be due to  [known issue](https://github.com/aws/containers-roadmap/issues/1389) in the CoreDNS AddOn and should be fixed in a future release.
To fix this error, please run the `delete-addon` command below first and then re-run the `apply-custom-runtime` step from above.

```
Error: waiting for EKS Add-On (htc-main:coredns) create: timeout while waiting for state to become 'ACTIVE' (last state: 'DEGRADED', timeout: 2m0s)
```

```
aws eks delete-addon --cluster-name htc-$TAG --addon coredns
```
{{% /notice %}}


{{% notice warning %}}
If your installation fails with the following error, then re-running `apply-custom-runtime` will fix the issue. This is a cross dependency issue when creating private APIs but haven't yet created an attachment to the policy itself (which requires the API to exist to reflect the correct resources).
```
Error: creating API Gateway Deployment: BadRequestException: Private REST API doesn't have a resource policy attached to it
```
{{% /notice %}}

### Validating HTC-Grid Deployment

If `terraform apply` is successful then in the terraform folder two files are created:

* **kubeconfig_htc_$TAG**: this file will give you access to the EKS cluster through kubectl
* **Agent_config.json**: this file contains all the parameters, so the agent can run in the infrastructure

Let's validate that the Compute Plane has been set up accordingly. First of all, we need to configure our environment with [Kubectl](https://kubernetes.io/docs/tasks/tools/) configuration pointing to our cluster. We will also read from the terraform output the Agent config file and prepare our environment to select the configuration on newly created terminals.

  ```
  cd ~/environment/aws-htc-grid/deployment/grid/terraform
  export AGENT_CONFIG_FILE=$(terraform output -raw agent_config)
  echo "export AGENT_CONFIG_FILE=$AGENT_CONFIG_FILE" >> ~/.bashrc
  ```

With this done, we can get the number of nodes in the cluster using the following command:

  ```
  kubectl get nodes
  ```

{{% notice tip %}}
You should have one or more nodes. If not please review the configuration files and particularly the variable `eks_worker_groups`
{{% /notice %}}

To check that the HTC-Agent is running on the system, you can run the following command:

  ```
  kubectl get pods
  ```

Finally to check all the deployments are running as expected, 

  ```
  kubectl get pods --all-namespaces
  ```

{{% notice note %}}
You should have all your pods in a running state, this might take a couple of minutes.
{{% /notice %}}
