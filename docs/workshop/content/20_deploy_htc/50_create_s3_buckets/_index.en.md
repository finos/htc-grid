---
title: "Creation of S3 Buckets"
chapter: false
weight: 50
---

In the previous step, we created a set of variables that reference S3 buckets. Let's describe first how are those variables used.

* **S3_UUID** we created a unique UUID to ensure the buckets created are unique, this unique UUID segment is used in the three environment variables with the S3 bucket names that follow.

* **S3_IMAGE_TFSTATE_HTCGRID_BUCKET_NAME**: The environment variable for the S3 bucket that holds the terraform state to transfer htc-grid docker images to your ECR repository.

* **S3_TFSTATE_HTCGRID_BUCKET_NAME**: The environment variable for the S3 bucket that holds terraform state for the installation of the htc-grid project

* **S3_LAMBDA_HTCGRID_BUCKET_NAME**: The environment variable for the S3 bucket that holds the code to be executed when a task is invoked.

## Create S3 Buckets

The following step creates the S3 buckets that will be needed during the installation:

```
aws s3 --region $HTCGRID_REGION mb s3://$S3_IMAGE_TFSTATE_HTCGRID_BUCKET_NAME
aws s3 --region $HTCGRID_REGION mb s3://$S3_TFSTATE_HTCGRID_BUCKET_NAME
aws s3 --region $HTCGRID_REGION mb s3://$S3_LAMBDA_HTCGRID_BUCKET_NAME
```

To validate the creation of the S3 buckets, you can run

```
aws s3 ls | grep $S3_UUID
```

That will list the 3 S3 Buckets that we just created.
