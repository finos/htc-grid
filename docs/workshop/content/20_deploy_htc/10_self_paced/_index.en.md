---
title: "...on your own"
chapter: false
weight: 10
---

{{% notice warning %}}
Only complete this section if you are running the workshop on your own. If you are at an AWS hosted event (such as re:Invent, Kubecon, Immersion Day, o any even hosted by an AWS employee etc), go to [Start the workshop at an AWS event]({{< ref "20_deploy_htc/20_aws_event/_index.en.md" >}}).
{{% /notice %}}

## Running the workshop on your own

### Creating an Admin User account

{{% notice warning %}}
Your account must have the ability to create new IAM roles and scope other IAM permissions.
{{% /notice %}}

1. If you don't already have an AWS account with Administrator access: [create
one now by clicking here](https://aws.amazon.com/getting-started/)

1. Once you have an AWS account, ensure you are following the remaining workshop steps
as an IAM user with administrator access to the AWS account:
[Create a new IAM user to use for the workshop](https://console.aws.amazon.com/iam/home?#/users$new)

1. Enter the user details:
{{< img "iam-1-create-user.png"  "iam-1-create-user" >}}

1. Attach the AdministratorAccess IAM Policy:
{{< img "iam-2-attach-policy.png"  "iam-2-attach-policy" >}}

1. Click to create the new user:
{{< img "iam-3-create-user.png"  "iam-3-create-user" >}}

1. Take note of the login URL and save:
{{< img "iam-4-save-url.png"  "iam-4-save-url" >}}


Once you have completed the step above, **you can head straight to [Configure your Workspace]({{< ref "/20_deploy_htc/30_configure_your_workspace/_index.en.md" >}})**



### Deploying Cloud9 Workspace

For first time users, windows users or those running within a workshop, we do recommend the use of Cloud9 as the platform to deploy HTC-Grid. HTC-Grid installation process uses Terraform and also `make` to build up artifacts and environment. 

HTC-Grid project provides a CloudFormation Cloud9 Stack that installs all the pre-requisites needed to deploy and develop HTC-Grid. 

Just follow the process below in your account to deploy the Cloud9 Cloudformation Stack. 

{{% notice info %}}
If you would like to use the current version of the project, change the value of the `HTCGridVersion` field to `main` in step 4 below.
{{% /notice %}}

1. Download the latest HTC-Grid Cloud9 Cloudformation Stack. **[The stack is available on this link](https://raw.githubusercontent.com/awslabs/aws-htc-grid/main/deployment/dev_environment_cloud9/cfn/cloud9-htc-grid.yaml)**.

1. On the AWS Console, select **CloudFormation** and **Create a Stack**. Select the (with new resources, Standard)

1. Select the **Template is ready** and then the **"Upload template file"**. Click on the **Choose File** button and select the `cloud9-htc-grid.yaml` that you downloaded in the previous step

    {{< img "Cloud9-stack-creation-1.png" "Cloud9 stack creation 1" >}}

1. Set the name of the stack to **htc-grid-workshop**. With a memorable name, later on it will be easier to identify and clean up the resources. Click on **Next**.

    {{< img "Cloud9-stack-creation-2.png" "Cloud9 stack creation 2" >}}

1. Scroll down on the next screen and click **Next** again, this will get you to the **Review htc-grid-workshop** page

1. Scroll down to the bottom of the **Review htc-grid-workshop** page, tick on the **Capabilities** check-box and click then on **Create Stack**

    {{< img "Cloud9-stack-creation-3.png" "Cloud9 stack creation 3" >}}

1. Finally wait for the CloudFormation Stack to complete. This may take a few minutes (From 10 to 15 minutes) You can use the time to [Read the CloudFormation stack](https://github.com/awslabs/aws-htc-grid/blob/main/deployment/dev_environment_cloud9/cfn/cloud9-htc-grid.yaml) and understand which resources have been deployed.


Once the CloudFormation Stack creation is complete, go to the **[Configure your Workspace]({{< ref "20_deploy_htc/30_configure_your_workspace/_index.en.md" >}})** section