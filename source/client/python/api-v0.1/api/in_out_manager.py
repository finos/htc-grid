# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import logging

from api.in_out_s3 import InOutS3
from api.in_out_redis import InOutRedis

"""
This function will create appropriate InOut Storage Object depending on the configuration string.
Valid Configurations <service type>

"grid_storage_service" : "S3"
"grid_storage_service" : "REDIS"
"grid_storage_service" : "S3+REDIS"


"""

logging.basicConfig(
    format="%(asctime)s - %(levelname)s - %(filename)s - %(funcName)s  - %(lineno)d - %(message)s",
    datefmt="%H:%M:%S",
    level=logging.INFO,
)
logging.info("Init AWS Grid Connector")


def in_out_manager(
    grid_storage_service,
    s3_bucket,
    redis_url,
    redis_password,
    s3_kms_key_id=None,
    s3_region=None,
    s3_custom_resource=None,
    redis_custom_connection=None,
):
    """This function returns a connection to the data plane. This connection will be used for uploading and
       downloading the payload associated to the tasks

    Args:
        grid_storage_service(string): the type of storage deployed with the data plane
        s3_bucket(string): the name of the S3 bucket (valid only if an S3 bucket has been deployed with data plane)
        s3_kms_key_id(string): the KMS Key ID of the S3 bucket (valid only if an S3 bucket has been deployed with data plane)
        s3_region(string): the region where the s3 has been created
        redis_url(string): the URL of the redis cluster (valid only if redis has been deployed with data plane)
        redis_password(string): the authentication password of the redis cluster (valid only if redis has been deployed with data plane)
        s3_custom_resource(object): override the default connection to AWS S3 service (valid only if an S3 bucket has been deployed with data plane)
        redis_custom_connection(object): override the default connection to the redis cluster (valid only if redis has been deployed with data plane)

    Returns:
        object: a connection to the data plane
    """
    logging.info(
        " storage_type {} s3 bucket {} s3_kms_key_id {} redis_url {}".format(
            grid_storage_service, s3_bucket, s3_kms_key_id, redis_url
        )
    )
    if grid_storage_service == "S3":
        return InOutS3(
            namespace=s3_bucket, region=s3_region, s3_kms_key_id=s3_kms_key_id
        )

    elif grid_storage_service == "REDIS":
        return InOutRedis(
            namespace=s3_bucket,
            cache_url=redis_url,
            cache_password=redis_password,
            use_S3=False,
            s3_kms_key_id=s3_kms_key_id,
            s3_custom_resource=s3_custom_resource,
            redis_custom_connection=redis_custom_connection,
        )

    elif grid_storage_service == "S3+REDIS":
        return InOutRedis(
            namespace=s3_bucket,
            cache_url=redis_url,
            cache_password=redis_password,
            use_S3=True,
            s3_kms_key_id=s3_kms_key_id,
            region=s3_region,
            s3_custom_resource=s3_custom_resource,
            redis_custom_connection=redis_custom_connection,
        )

    else:
        raise Exception(
            "InOutManager can not parse connection string: {}".format(
                grid_storage_service
            )
        )
