# Copyright 2024 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

from influxdb import InfluxDBClient


class PerfTrackerInfluxDBConnector:
    def __init__(self, connector_string, influxdb_ip):
        """
        Expected format of the connection string:
        "<aws_region_name> <firehose_stream_name>"
        example:
        "eu-west-1 fh_submit_tasks_lambda"
        """

        tokens = connector_string.split(" ")
        self.influxdb_ip = influxdb_ip
        self.influxdb_port = tokens[0]
        self.database = tokens[1]
        self.measurement = tokens[2]

        print(self.influxdb_ip, self.influxdb_port, self.database, self.measurement)

        # self.firehose_client = boto3.client('firehose',  region_name=self.region_name)
        # self.firehose_client = boto3.client('firehose',  region_name=self.region_name, endpoint_url="https://firehose.eu-west-1.amazonaws.com")

        self.influxdb_client = InfluxDBClient(
            host=self.influxdb_ip, port=self.influxdb_port
        )

        self.influxdb_client.create_database(self.database)
        self.influxdb_client.switch_database(self.database)

        self.samples_buffer = []

    def add_sample(self, json_data_sample):
        fields = {}

        for k, v in json_data_sample.items():
            fields[k] = v

        sample = {
            "measurement": self.measurement,
            "time": json_data_sample["EVENT_TIME"],
            "fields": fields,
        }

        self.samples_buffer.append(sample)

    def submit_measurements(self):
        print(self.samples_buffer)
        res = self.influxdb_client.write_points(self.samples_buffer)

        self.samples_buffer = []

        return res
