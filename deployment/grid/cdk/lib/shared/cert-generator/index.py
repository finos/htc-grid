# Copyright 2022 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


import boto3
import logging
import json

logger = logging.getLogger()
logger.setLevel(logging.INFO)

client = boto3.client('acm')

def handler(event, context):
    if event['RequestType'] == 'Create':
        return createCert(event)    
    elif event['RequestType'] == 'Update':
        return updateCert(event)
    elif event['RequestType'] == 'Delete':
        return deleteCert(event)
    else:
        logger.info('Unknown event request type!')

def createCert(event):
    props = event['ResourceProperties']
    
    cert = props['Certificate']
    pk = props['PrivateKey']
    
    response = client.import_certificate(
        Certificate=cert.encode(),
        PrivateKey=pk.encode()
    )
    
    cert_arn = response['CertificateArn']
    
    return { 'PhysicalResourceId': cert_arn, 'Data': { 'CertificateArn': cert_arn } }

def updateCert(event):
    cert_arn = event['PhysicalResourceId']
    
    return { 'PhysicalResourceId': cert_arn, 'Data': { 'CertificateArn': cert_arn } }
    
def deleteCert(event):
    cert_arn = event['PhysicalResourceId']
    
    response = client.delete_certificate(
        CertificateArn=cert_arn
    )
    
    return
