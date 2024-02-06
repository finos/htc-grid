# Copyright 2024 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import json
import datetime
import random
import boto3


class PerfTrackerFirehoseConnector:
    def __init__(self, connector_string):
        """
        Expected format of the connection string:
        "<aws_region_name> <firehose_stream_name>"
        example:
        "eu-west-1 fh_submit_tasks_lambda"
        """

        tokens = connector_string.split(" ")
        self.region_name = tokens[0]
        self.delivery_stream_name = tokens[1]

        # self.firehose_client = boto3.client('firehose',  region_name=self.region_name)
        self.firehose_client = boto3.client(
            "firehose",
            region_name=self.region_name,
            endpoint_url=f"https://firehose.{self.region_name}.amazonaws.com",
        )

        self.samples_buffer = []

    def __build_msg(self):
        return {
            "measurement": "event1",
            "time": datetime.datetime.utcnow(),
            "fields": {
                "duration": random.randint(0, 1000),
            },
        }

    def add_sample(self, json_data_sample):
        sample = {"Data": json.dumps(json_data_sample)}

        self.samples_buffer.append(sample)

    def submit_measurements(self):
        res = self.firehose_client.put_record_batch(
            DeliveryStreamName=self.delivery_stream_name, Records=self.samples_buffer
        )

        self.samples_buffer = []

        return res
