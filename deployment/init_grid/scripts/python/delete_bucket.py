#!/usr/bin/env python

import sys
import boto3

if len(sys.argv) < 2:
    print("Please provide one bucket name as a command line argument")
    sys.exit(1)

bucket_name = sys.argv[1]

s3 = boto3.resource("s3")
bucket = s3.Bucket(bucket_name)

s3_client = boto3.client("s3")
versioning = s3_client.get_bucket_versioning(Bucket=bucket_name)

if versioning.get("Status") == "Enabled":
    bucket.object_versions.delete()
    print("Succesfully deleted all bucket object versions in bucket: {0}".format(bucket_name))
else:
    bucket.objects.delete()
    print("Succesfully deleted all bucket objects in bucket: {0}".format(bucket_name))


s3_client.delete_bucket(Bucket=bucket_name)
print("Succesfully deleted bucket: {0}".format(bucket_name))
