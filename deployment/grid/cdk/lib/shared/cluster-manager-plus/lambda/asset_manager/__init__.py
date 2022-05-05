import boto3
import zipfile
import logging
import json
import shutil

logger = logging.getLogger()
logger.setLevel(logging.INFO)
s3 = boto3.client('s3')

def asset_file(asset, out_path):
    bucket = asset['Bucket']
    object_key = asset['ObjectKey']
    logger.info(f'Pulling {object_key} from {bucket}')
    s3.download_file(bucket, object_key, out_path)
    logger.info(f'{object_key} downloaded to: {out_path}')

def asset_directory(asset, out_path):
    zip_path = '/tmp/tmp-zip.zip'
    asset_file(asset, zip_path)
    clean_directory(out_path)
    with zipfile.ZipFile(zip_path, 'r') as zip_ref:
        zip_ref.extractall(out_path)
    logger.info(f'Object extracted to: {out_path}')

def clean_directory(path):
    # Try to remove existing helm directory if Lambda is reusing container
    try:
        shutil.rmtree(path, ignore_errors=True)
        logger.info(f'Removed old dir: {path}')
    except OSError as e:
        print ("Error: %s - %s." % (e.filename, e.strerror))
          