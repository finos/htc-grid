+++
title = "Cleanup"
chapter = false
weight = 50
pre = "<b>5. </b>"
+++

Before closing the session we should cleanup the environment. 

{{% notice note %}}
If you are running the workshop at an AWS event, you can skip this section. We still encourage you to go through it so you understand however what are the steps to cleanup the resources that were created by HTC-Grid during this workshop
{{% /notice %}}


### Cleanup HTC-Grid Deployment

To remove and destroy all the resources deployed within HTC-Grid and delete the locally cached modules, run the following commands:

```
make destroy-python-runtime TAG=$TAG REGION=$HTCGRID_REGION
make reset-grid-deployment TAG=$TAG REGION=$HTCGRID_REGION
```

{{% notice warning %}}
The destruction of some of the resources may take some time. If for whatever reason there are errors due to timeouts, just re-run the command above. Terraform will track the resources that still exist and remove them.
{{% /notice %}}


### Cleanup HTC-Grid ECR Images

To clean up the images and repositories from ECR and delete the locally cached modules, run the following commands:

```
make destroy-images TAG=$TAG REGION=$HTCGRID_REGION
make reset-images-deployment TAG=$TAG REGION=$HTCGRID_REGION
```

### Cleanup of the S3 buckets

{{% notice warning %}}
You should leave this step for the very end, once that all the other cleanup processes above have concluded successfully. These buckets contain the state of your Terraform deployments, thus, removing them before destroying the relevant Terraform resources will mean that you will be left with orphaned resources which you will need to clean up manually.
{{% /notice %}}


Finally, we will delete CloudFormation stack which manages the S3 buckets that contain our Terraform state, by running the following command:

```
make delete-grid-state TAG=$TAG REGION=$HTCGRID_REGION
```
