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
The destruction of some of the resources may take some time. If for whatever reason there are errors due to timeouts, just re-run the command above. Terraform will track down which resources are still up and remove the resources.
{{% /notice %}}


### Cleanup HTC-Grid ECR Images

To clean up the images and repositories from ECR and delete the locally cached modules, run the following commands:

```
make destroy-images TAG=$TAG REGION=$HTCGRID_REGION
make reset-images-deployment TAG=$TAG REGION=$HTCGRID_REGION
```

### Cleanup of the S3 buckets

{{% notice warning %}}
You should leave this for the very end once that all the other cleanup processes above have concluded successfully. Terraform state buckets contain the state of your terraform deployments, removing the buckets will mean your terraform will loose track of the state.
{{% /notice %}}


Finally, this will leave the 3 only resources that you can clean manually, the S3 buckets. You can remove the folders using the following command.

```
make delete-grid-state TAG=$TAG REGION=$HTCGRID_REGION
```


