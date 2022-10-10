# Copyright 2022 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


import json
import logging
import os
import subprocess

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# these are coming from the kubectl layer
os.environ['PATH'] = '/opt/kubectl:/opt/awscli:' + os.environ['PATH']

outdir = os.environ.get('TEST_OUTDIR', '/tmp')
kubeconfig = os.path.join(outdir, 'kubeconfig')
cluster_name = os.environ['ClusterName']
role_arn = os.environ['RoleArn']

def custom_handler(event, context):
    logger.info(json.dumps(event))

    request_type = event['RequestType']
    props = event['ResourceProperties']

    # resource properties
    create_cmd    = props['CreateCommand']
    update_cmd    = props.get('UpdateCommand', None)
    delete_cmd    = props.get('DeleteCommand', None)

    # "log in" to the cluster
    cmd = [ 'aws', 'eks', 'update-kubeconfig',
        '--role-arn', role_arn,
        '--name', cluster_name,
        '--kubeconfig', kubeconfig
    ]
    logger.info(f'Running command: {cmd}')
    subprocess.check_call(cmd)

    if request_type == 'Create':
        try:
            kubectl(create_cmd)
        except Exception as e:
            logger.info("create error: %s" % e)
    elif request_type == 'Update' and not update_cmd is None:
        try:
            kubectl(update_cmd)
        except Exception as e:
            logger.info("update error: %s" % e)
    elif request_type == "Delete" and not delete_cmd is None:
        try:
            kubectl(delete_cmd)
        except Exception as e:
            logger.info("delete error: %s" % e)


def kubectl(custom_cmd):
    maxAttempts = 3
    retry = maxAttempts
    cmd = 'kubectl ' + custom_cmd + ' --kubeconfig ' + kubeconfig
    
    while retry > 0:
        try:
            logger.info(f'Running command: {cmd}')
            output = subprocess.check_output(cmd, stderr=subprocess.STDOUT, shell=True)
        except subprocess.CalledProcessError as exc:
            output = exc.output
            if b'i/o timeout' in output and retry > 0:
              retry = retry - 1
              logger.info("kubectl timed out, retries left: %s" % retry)
            else:
                raise Exception(output)
        else:
            logger.info(output)
            return
    raise Exception(f'Operation failed after {maxAttempts} attempts: {output}')