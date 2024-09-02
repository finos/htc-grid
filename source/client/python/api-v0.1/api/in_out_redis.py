# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import boto3
import sys
import io
import redis

INPUT_POSTFIX = "-input"
OUTPUT_POSTFIX = "-output"
ERROR_POSTFIX = "-error"
PAYLOAD_POSTFIX = "-payload"


class InOutRedis:
    """Simple S3 based handler for putting and retrieving large values associated with taskIDs"""

    # For S3 implementation , namespace is a bucket name
    namespace = None
    cache_url = None
    cache_password = None

    redis_cache = None
    redis_pubsub = None

    s3 = None

    def __init__(
        self,
        namespace,
        cache_url,
        cache_password,
        subnamespace=None,
        use_S3=False,
        s3_kms_key_id=None,
        region=None,
        s3_custom_resource=None,
        redis_custom_connection=None,
    ):
        """
        Initialize a connection with data plane backed by a Redis cluster and optionally a S3 Bucket
        Args:
            namespace(string): namespace of the S3 Bucket
            cache_url(string): URL of the redis cluster
            cache_password(string): AUth password of the redis cluster
            subnamespace(string): subnamespace of the S3 bucket
            use_S3(bool): add S3 as additional backend for the dataplane
            s3_kms_key_id(string): the KMS Key ID of the S3 bucket (valid only if an S3 bucket has been deployed with data plane)
            region(string): region where the s3 bucket has been created
            s3_custom_resource(object): override default S3 resource
            redis_custom_connection(object): override default redis connection
        """
        self.namespace = namespace
        self.cache_url = cache_url
        self.cache_password = cache_password
        self.subnamespace = subnamespace

        if use_S3:
            if s3_custom_resource is None:
                self.s3 = boto3.resource("s3", region_name=region)
            else:
                self.s3 = s3_custom_resource
            self.bucket = self.s3.Bucket(self.namespace)
            self.s3_kms_key_id = s3_kms_key_id
        else:
            self.bucket = None
            self.s3_kms_key_id = None

        if redis_custom_connection is None:
            self.redis_cache = redis.StrictRedis(
                host=cache_url, ssl=True, password=cache_password
            )
        else:
            self.redis_cache = redis_custom_connection

    def put_input_from_file(self, task_id, file_name):
        self.__put_from_file(task_id, file_name, INPUT_POSTFIX)

    def put_output_from_file(self, task_id, file_name):
        self.__put_from_file(task_id, file_name, OUTPUT_POSTFIX)

    def put_error_from_file(self, task_id, file_name):
        self.__put_from_file(task_id, file_name, ERROR_POSTFIX)

    def put_input_from_bytes(self, task_id, data):
        self.__put_from_bytes(task_id, data, INPUT_POSTFIX)

    def put_output_from_bytes(self, task_id, data):
        self.__put_from_bytes(task_id, data, OUTPUT_POSTFIX)

    def put_payload_from_bytes(self, task_id, data):
        self.__put_from_bytes(task_id, data, PAYLOAD_POSTFIX)

    def put_payload_from_file(self, task_id, file_name):
        self.__put_from_file(task_id, file_name, PAYLOAD_POSTFIX)

    def get_input_to_utf8_string(self, task_id):
        return self.__get_to_utf8_string(task_id, INPUT_POSTFIX)

    def get_output_to_utf8_string(self, task_id):
        return self.__get_to_utf8_string(task_id, OUTPUT_POSTFIX)

    def get_input_to_bytes(self, task_id):
        return self.__get_to_bytes(task_id, INPUT_POSTFIX)

    def get_output_to_bytes(self, task_id):
        return self.__get_to_bytes(task_id, OUTPUT_POSTFIX)

    def get_payload_to_utf8_string(self, task_id):
        return self.__get_to_utf8_string(task_id, PAYLOAD_POSTFIX)

    def get_payload_to_bytes(self, task_id):
        return self.__get_to_bytes(task_id, PAYLOAD_POSTFIX)

    def __get_full_key(self, key, postfix):
        if self.subnamespace is not None:
            return str(self.subnamespace) + "/" + str(key) + str(postfix)
        else:
            return str(key) + str(postfix)

    ##################################################################################
    # MIGHT NEED TO QUIT THE CONNECTION? IE CREATE THE CONNECTION WHEN NEEDED ONLY?###
    ##################################################################################

    def __put_from_file(self, task_id, file_name, postfix):
        try:
            if self.bucket:
                self.bucket.upload_file(
                    Filename=file_name,
                    Key=self.__get_full_key(task_id, postfix),
                    ExtraArgs={
                        "ServerSideEncryption": "AES256",
                        "SSEKMSKeyId": self.s3_kms_key_id,
                    },
                )

            in_file = open(file_name, "rb")

            file_content = in_file.read()

            in_file.close()

            self.redis_cache.set(self.__get_full_key(task_id, postfix), file_content)

        except Exception as e:
            print(e, file=sys.stderr)
            raise e

    def __put_from_bytes(self, task_id, data, postfix):
        try:
            if self.bucket:
                with io.BytesIO(data) as f_data:
                    self.bucket.upload_fileobj(
                        Fileobj=f_data,
                        Key=self.__get_full_key(task_id, postfix),
                        ExtraArgs={
                            "ServerSideEncryption": "AES256",
                            "SSEKMSKeyId": self.s3_kms_key_id,
                        },
                    )

            self.redis_cache.set(self.__get_full_key(task_id, postfix), data)

        except Exception as e:
            print(e)
            raise e

    def __get_to_bytes(self, task_id, postfix):
        try:
            content = self.redis_cache.get(self.__get_full_key(task_id, postfix))
            if content is None:
                # cache miss
                print("Cache miss for " + task_id)

                if self.bucket:
                    with io.BytesIO() as f_data:
                        self.bucket.download_fileobj(
                            Key=self.__get_full_key(task_id, postfix), Fileobj=f_data
                        )
                        data = f_data.getvalue()

                    if not data:
                        raise Exception("Can not retrieve from S3 {} ".format(task_id))

                    self.redis_cache.set(self.__get_full_key(task_id, postfix), data)
                    return data
                else:
                    raise Exception("Cache miss for {}".format(task_id))
            else:
                return content
        except Exception as e:
            print(e)
            raise e

    def __get_to_utf8_string(self, task_id, postfix):
        try:
            content = self.redis_cache.get(self.__get_full_key(task_id, postfix))
            if content is None:
                # cache miss
                print("Cache miss for " + task_id)

                if self.bucket:
                    with io.BytesIO() as f_data:
                        self.bucket.download_fileobj(
                            Key=self.__get_full_key(task_id, postfix), Fileobj=f_data
                        )
                        data = f_data.getvalue()

                    if not data:
                        raise Exception("Can not retrieve from S3 {} ".format(task_id))

                    self.redis_cache.set(self.__get_full_key(task_id, postfix), data)

                    return data.decode("utf-8")
                else:
                    raise Exception("Cache miss for {}".format(task_id))

            else:
                return content.decode("utf-8")
        except Exception as e:
            print(e)
            raise e
