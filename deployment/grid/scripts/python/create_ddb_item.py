
# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


import uuid
import boto3
import time
import os


def lambda_handler(event, context):
    dynamodb = boto3.resource('dynamodb',region_name="eu-west-1")
    table = dynamodb.Table(os.environ['TASKS_STATUS_TABLE_NAME'])
    for i  in range(20):
        session_id = uuid.uuid1()
        task_id = uuid.uuid1()
        time_now_ms = time_now_ms = int(round(time.time() * 1000))
        table.put_item(Item={
            #'session_id': str(session_id),
            'task_id': str(task_id),
            'submission_timestamp': time_now_ms,
            'task_completion_timestamp': 0,
            'task_status': "pending",
            'task_owner': "None",
            'retries': 0,
            'task_definition': "task definition",
            'sqs_handler_id': "None",
            'heartbeat_expiration_timestamp': 0
        }
    )



def main():
    res = lambda_handler(event= {}, context=None)
    print (res)


if __name__ == "__main__":
    # execute only if run as a script
    os.environ["TASKS_STATUS_TABLE_NAME"] = "tasks_status_table_kgrid_team"
    main()