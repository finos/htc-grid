import boto3
import time
import logging
import json

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    if event['RequestType'] == 'Create':
        logger.info(json.dumps(event))
        checkNodegroup(event)
        
def checkNodegroup(event):
    props = event['ResourceProperties']
        
    client = boto3.client('eks')
    
    cluster = props['Cluster']
    nodegroup = props['Nodegroup']
    
    logger.info(f'Checking to see if nodegroup: {nodegroup} is ready...')
    
    response = client.describe_nodegroup(
        clusterName=cluster,
        nodegroupName=nodegroup
    )
    
    status = response['nodegroup']['status']
    if (status == 'ACTIVE'):
        logger.info('Nodegroup active!')
        return
    logger.info('Nodegroup not active yet, sleeping...')
    time.sleep(15) 
    checkNodegroup(event)
