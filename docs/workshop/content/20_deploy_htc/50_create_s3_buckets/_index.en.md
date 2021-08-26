---
title: "Creation of S3 Buckets"
chapter: false
weight: 50
---


## Create S3 Buckets

The following step creates 3 S3 buckets that will be needed during the installation:

```
make init-grid-state  TAG=$TAG REGION=$HTCGRID_REGION
```

To validate the creation of the S3 buckets, you can run

```
aws cloudformation describe-stacks --stack-name $TAG --region $HTCGRID_REGION --query 'Stacks[0]'
```

That will list the 3 S3 Buckets that we just created.
