import json
import logging
import os
import subprocess
import boto3
import asset_manager

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# these are coming from the kubectl layer
os.environ['PATH'] = '/opt/helm:/opt/awscli:' + os.environ['PATH']

outdir = os.environ.get('TEST_OUTDIR', '/tmp')
kubeconfig = os.path.join(outdir, 'kubeconfig')
cluster_name = os.environ['ClusterName']
role_arn = os.environ['RoleArn']

chart_dir = os.path.join(outdir, 'helm')

def helm_handler(event, context):
    logger.info(json.dumps(event))

    request_type = event['RequestType']
    props = event['ResourceProperties']

    # resource properties
    release      = props['Release']
    chart        = props['Chart']
    local_chart  = props['LocalChart']
    chart_asset  = props.get('S3Chart', None)
    values_assets= props.get('S3Values', None)
    version      = props.get('Version', None)
    wait         = props.get('Wait', False)
    timeout      = props.get('Timeout', None)
    namespace    = props.get('Namespace', None)
    create_namespace = props.get('CreateNamespace', None)
    repository   = props.get('Repository', None)
    values_text  = props.get('Values', None)

    # "log in" to the cluster
    subprocess.check_call([ 'aws', 'eks', 'update-kubeconfig',
        '--role-arn', role_arn,
        '--name', cluster_name,
        '--kubeconfig', kubeconfig
    ])

    if request_type == 'Create' or request_type == 'Update':
        # Write out the values to a file and include them with the install and upgrade
        values_files = []
        if not values_text is None or not values_assets is None:
            if not values_text is None:
                values = json.loads(values_text)
                values_file = os.path.join(outdir, 'values.yaml')
                with open(values_file, "w") as f:
                    f.write(json.dumps(values, indent=2))
                values_files.append(values_file)
            if not values_assets is None:
                i = 1
                for asset in values_assets:
                    out_file = os.path.join(outdir, f'values{i}.yaml')
                    asset_manager.asset_file(asset, out_file)
                    values_files.append(out_file)
                    i = i+1
        if local_chart == 'true':
            asset_manager.asset_directory(chart_asset, chart_dir)
        helm('upgrade', release, local_chart, chart, repository, values_files, namespace, version, wait, timeout, create_namespace)
    elif request_type == "Delete":
        try:
            helm('uninstall', release, local_chart, namespace=namespace, timeout=timeout)
        except Exception as e:
            logger.info("delete error: %s" % e)

def helm(verb, release, local_chart, chart = None, repo = None, files = None, namespace = None, version = None, wait = False, timeout = None, create_namespace = None):
    import subprocess

    cmnd = ['helm', verb, release]
    if not chart is None and local_chart == 'false':
        cmnd.append(chart)
    if local_chart == 'true' and verb != 'uninstall':
        cmnd.append(chart_dir)
    if verb == 'upgrade':
        cmnd.append('--install')
    if create_namespace:
        cmnd.append('--create-namespace')
    if not repo is None and local_chart == 'false':
        cmnd.extend(['--repo', repo])
    if not files is None and len(files) > 0:
        for file in files:
        #     logger.info(f'appending file: {file}')
        #     with open(file, 'r') as f:
        #         logger.info(f.read())
            cmnd.extend(['--values', file])
    if not version is None:
        cmnd.extend(['--version', version])
    if not namespace is None:
        cmnd.extend(['--namespace', namespace])
    if wait:
        cmnd.append('--wait')
    if not timeout is None:
        cmnd.extend(['--timeout', timeout])
    cmnd.extend(['--kubeconfig', kubeconfig])

    logger.info(f'Running command: {cmnd}')
    maxAttempts = 3
    retry = maxAttempts
    while retry > 0:
        try:
            output = subprocess.check_output(cmnd, stderr=subprocess.STDOUT, cwd=outdir)
            logger.info(output)
            return
        except subprocess.CalledProcessError as exc:
            output = exc.output
            if b'Broken pipe' in output:
                retry = retry - 1
                logger.info("Broken pipe, retries left: %s" % retry)
            else:
                raise Exception(output)
    raise Exception(f'Operation failed after {maxAttempts} attempts: {output}')