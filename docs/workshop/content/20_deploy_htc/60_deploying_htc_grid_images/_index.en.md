---
title: "Copy dependencies to ECR"
chapter: false
weight: 60
---

The HTC-Grid project has external software dependencies that are deployed as container images. Instead of downloading each time from external repositories like the public DockerHub repository, this step will pull those dependencies and upload them into the your [Amazon Elastic Container Registry (ECR)](https://aws.amazon.com/ecr/).

{{% notice warning %}}
HTC-Grid uses a few open source project with container images stored at Dockerhub. Dockerhub has a download rate limit policy. This may impact you when running this step as an anonymous user as you can get errors when running the terraform command below. To overcome those errors, you can re-run the terraform command and wait until the throttling limit is lifted, or optionally you can create an account in hub.docker.com and then use the credentials of the account using docker login locally to avoid anonymous throttling limitations.
{{% /notice %}}

1. As you'll be uploading images to ECR, to avoid timeouts, refresh your ECR authentication token:

    ```
    aws ecr get-login-password --region $HTCGRID_REGION | docker login --username AWS --password-stdin $HTCGRID_ACCOUNT_ID.dkr.ecr.$HTCGRID_REGION.amazonaws.com
    ```
1. Go into the terraform image deployment directory. This contains the terraform project that will help to create a copy of the required images to your ECR repository. The following command will go to the `~/environment/aws-htc-grid/deployment/image_repository/terraform` and initialize the terraform project using the bucket `$S3_IMAGE_TFSTATE_HTCGRID_BUCKET_NAME` as the bucket that will hold the terraform state:

    ```
    cd ~/environment/aws-htc-grid/deployment/image_repository/terraform
    terraform init -backend-config="bucket=$S3_IMAGE_TFSTATE_HTCGRID_BUCKET_NAME" \
                -backend-config="region=$HTCGRID_REGION"
    ```

1. If successful, you can now run terraform apply to create the HTC-Grid infrastructure. This can take between 10 and 15 minutes depending on the Internet connection.

    ```
    terraform apply -var-file ./images_config.json -var "region=$HTCGRID_REGION" -parallelism=1
    ```
{{% notice note %}}
The execution of this command will prompt for `yes` to continue. Just type yes, for the command to proceed
{{% /notice %}}

{{% notice info %}}
This operation fetches images from external repositories and creates a copy into your ECR account, sometimes the fetch to external repositories may have temporary failures due to the state of the external repositories, If the `terraform apply` fails with errors such as `name unknown: The repository with name 'xxxxxxxxx' does not exist in the registry with id`, re-run the command until the `terraform apply` step successfully completes. 
{{% /notice %}}

The following command will list the repositories You can check which repositories have been created in the ECR console or by executing the command :

```
aws ecr describe-repositories --query "repositories[*].repositoryUri"
```

