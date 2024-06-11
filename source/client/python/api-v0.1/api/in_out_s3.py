# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import boto3
import sys
import io
import logging

logging.basicConfig(
    format="%(asctime)s - %(levelname)s - %(filename)s - %(funcName)s  - %(lineno)d - %(message)s",
    datefmt="%H:%M:%S",
    level=logging.INFO,
)
logger = logging.getLogger(__name__)


INPUT_POSTFIX = "-input"
OUTPUT_POSTFIX = "-output"
ERROR_POSTFIX = "-error"
PAYLOAD_POSTFIX = "-payload"


class InOutS3:
    """Simple S3 based handler for putting and retreiving large values associated with taskIDs"""

    # For S3 implementation , namespace is a bucketname
    namespace = None
    # For S3 implementation , subnamespace is a directory
    subnamespace = None
    # S3 KMS Key ID
    s3_kms_key_id = None

    s3 = None

    def __init__(
        self,
        namespace,
        region,
        s3_kms_key_id,
        subnamespace=None,
        s3_custom_resource=None,
    ):
        """Initialize a dataplane backed by an S3 bucket

        Args:
            namespace(string): namespace of the S3 Bucket
            region(string): region where the s3 bucket has been created
            subnamespace(string): subnamespace of the S3 bucket
            s3_custom_resource(object): override default S3 resource
        """

        self.namespace = namespace
        self.subnamespace = subnamespace

        if s3_custom_resource is None:
            self.s3 = boto3.resource("s3", region_name=region)
            logger.warning("using s3 resource from AWS")
        else:
            self.s3 = s3_custom_resource
            logger.warning("using s3 resource from other provider")
        self.bucket = self.s3.Bucket(self.namespace)
        self.s3_kms_key_id = s3_kms_key_id

    def put_input_from_file(self, task_id, file_name):
        return self.__put_from_file(task_id, file_name, INPUT_POSTFIX)

    def put_output_from_file(self, task_id, file_name):
        return self.__put_from_file(task_id, file_name, OUTPUT_POSTFIX)

    def put_error_from_file(self, task_id, file_name):
        return self.__put_from_file(task_id, file_name, ERROR_POSTFIX)

    def get_input_to_file(self, task_id, file_name):
        return self.__get_to_file(task_id, file_name, INPUT_POSTFIX)

    def get_output_to_file(self, task_id, file_name):
        return self.__get_to_file(task_id, file_name, OUTPUT_POSTFIX)

    def get_error_to_file(self, task_id, file_name):
        return self.__get_to_file(task_id, file_name, ERROR_POSTFIX)

    def put_input_from_bytes(self, task_id, data):
        return self.__put_from_bytes(task_id, data, INPUT_POSTFIX)

    def put_output_from_bytes(self, task_id, data):
        return self.__put_from_bytes(task_id, data, OUTPUT_POSTFIX)

    def put_error_from_bytes(self, task_id, data):
        return self.__put_from_bytes(task_id, data, ERROR_POSTFIX)

    def get_input_to_utf8_string(self, task_id):
        return self.__get_to_utf8_string(task_id, INPUT_POSTFIX)

    def get_output_to_utf8_string(self, task_id):
        return self.__get_to_utf8_string(task_id, OUTPUT_POSTFIX)

    def get_error_to_utf8_string(self, task_id):
        return self.__get_to_utf8_string(task_id, ERROR_POSTFIX)

    def get_input_to_bytes(self, task_id):
        return self.__get_to_bytes(task_id, INPUT_POSTFIX)

    def get_output_to_bytes(self, task_id):
        return self.__get_to_bytes(task_id, OUTPUT_POSTFIX)

    def get_error_to_bytes(self, task_id):
        return self.__get_to_bytes(task_id, ERROR_POSTFIX)

    def put_payload_from_bytes(self, task_id, data):
        self.__put_from_bytes(task_id, data, PAYLOAD_POSTFIX)

    def put_payload_from_file(self, task_id, file_name):
        self.__put_from_file(task_id, file_name, PAYLOAD_POSTFIX)

    def get_payload_to_utf8_string(self, task_id):
        return self.__get_to_utf8_string(task_id, PAYLOAD_POSTFIX)

    def get_payload_to_bytes(self, task_id):
        return self.__get_to_bytes(task_id, PAYLOAD_POSTFIX)

    # Do we need to implement it for buffers?
    # def get_input_to_buffer(self, taskId):
    #     return self.__get_to_buffer(taskId, INPUT_POSTFIX)

    # def get_output_to_buffer(self, taskId):
    #     return self.__get_to_buffer(taskId, OUTPUT_POSTFIX)

    def __put_from_file(self, task_id, file_name, postfix):
        try:
            self.bucket.upload_file(
                Filename=file_name,
                Key=self.__get_full_key(task_id, postfix),
                ExtraArgs={
                    "ServerSideEncryption": "AES256",
                    "SSEKMSKeyId": self.s3_kms_key_id,
                },
            )
        except Exception as e:
            print(e, file=sys.stderr)
            raise e

    def __get_to_file(self, task_id, file_name, postfix):
        try:
            self.bucket.download_file(
                Key=self.__get_full_key(task_id, postfix), Filename=file_name
            )
        except Exception as e:
            print(e, file=sys.stderr)
            raise e

    def __put_from_bytes(self, task_id, data, postfix):
        try:
            with io.BytesIO(data) as f_data:
                self.bucket.upload_fileobj(
                    Fileobj=f_data,
                    Key=self.__get_full_key(task_id, postfix),
                    ExtraArgs={
                        "ServerSideEncryption": "AES256",
                        "SSEKMSKeyId": self.s3_kms_key_id,
                    },
                )
        except Exception as e:
            print(e, file=sys.stderr)
            raise e

    def __get_to_utf8_string(self, task_id, postfix):
        try:
            return self.__get_to_bytes(task_id, postfix).decode("utf-8")
        except Exception as e:
            print(e, file=sys.stderr)
            raise e

    def __get_to_bytes(self, task_id, postfix):
        try:
            with io.BytesIO() as f_data:
                self.bucket.download_fileobj(
                    Key=self.__get_full_key(task_id, postfix), Fileobj=f_data
                )
                return f_data.getvalue()
        except Exception as e:
            print(e, file=sys.stderr)
            raise e

    def __get_full_key(self, key, postfix):
        if self.subnamespace is not None:
            return str(self.subnamespace) + "/" + str(key) + str(postfix)
        else:
            return str(key) + str(postfix)

    def mv_to_another_namespace(
        self, key, new_namespace, new_subnamespace=None, new_key=None
    ):
        # S3 implmentation: namespace is a bucket, subnamespace a directory
        try:
            copy_source = {"Bucket": self.namespace, "Key": str(key)}
            # no renaming by default
            full_new_key = ""
            if new_subnamespace is not None:
                full_new_key += str(new_subnamespace) + "/"
            if new_key is not None:
                full_new_key += str(new_key)
            else:
                full_new_key += str(key)

            print(full_new_key)
            print(copy_source)
            target_bucket = self.s3.Bucket(new_namespace)
            target_bucket.copy(
                CopySource=copy_source,
                Key=full_new_key,
                ExtraArgs={
                    "ServerSideEncryption": "AES256",
                    "SSEKMSKeyId": self.s3_kms_key_id,
                },
            )
        except Exception as e:
            print(e, file=sys.stderr)
            raise e
