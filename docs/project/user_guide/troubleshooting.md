

## Troubleshooting HTC-Grid

This section captures some of the errors we have captured in the past and how to resolve them

## Error on terraform apply:
```
terraform apply -var-file ./../src/eks/Agent_config_mainline.json"
...
...

Error: DeleteConflict: Certificate: XXXXXXXXXXX is currently in use by arn:aws:elasticloadbalancing:eu-west-1:XXXXXXXXX:loadbalancer/app/k8s-grafana-grafanai-026d965437/c04519ef28804b31. Please remove it first before deleting it from IAM.
status code: 409, request id: 9e621094-2dba-44ac-967d-c764470c1474
```

### Resolution:
```
kubectl -n grafana get ingress

kubectl -n grafana delete ingress grafana-ingress

terraform apply -var-file ./../src/eks/Agent_config_mainline.json"

```


## Error from terraform Apply when pulling the images
```
Error: Error running command 'if ! docker pull curlimages/curl:7.73.0
then
  echo "cannot download image curlimages/curl:7.73.0"
  exit 1
fi
if ! docker tag curlimages/curl:7.73.0 300962108239.dkr.ecr.eu-west-1.amazonaws.com/curl:7.73.0
then
  echo "cannot tag curlimages/curl:7.73.0 to 300962108239.dkr.ecr.eu-west-1.amazonaws.com/curl:7.73.0"
  exit 1
fi
if ! docker push 300962108239.dkr.ecr.eu-west-1.amazonaws.com/curl:7.73.0
then
  echo "echo cannot push 300962108239.dkr.ecr.eu-west-1.amazonaws.com/curl:7.73.0"
  exit 1
fi
': exit status 1. Output: 7.73.0: Pulling from curlimages/curl
```
### Resolution

Rerun the terraform command, DockerHub has throttling limits that may cause spurious errors like this


## Error on terraform apply:
```
Error: cannot re-use a name that is still in use

  on resources/influxd.tf line 19, in resource "helm_release" "influxdb":
  19: resource "helm_release" "influxdb" {
```
### Resolution:
```
export HELM_DRIVER=configmap
helm list -n influxdb
helm -n influxdb uninstall influxdb
...
<restart tarraform apply>
```


## Error on terraform apply:

```
Error: error reading VPC Endpoint Service (com.amazonaws.eu-north-1.elasticloadbalancing): InvalidServiceName: The Vpc Endpoint Service 'com.amazonaws.eu-north-1.elasticloadbalancing' does not exist
	status code: 400, request id: 60127863-944c-467b-983b-8f8b79f332c0

  on .terraform/modules/vpc.vpc/vpc-endpoints.tf line 656, in data "aws_vpc_endpoint_service" "elasticloadbalancing":
 656: data "aws_vpc_endpoint_service" "elasticloadbalancing" {
```

### Resolution

Some AWS regions currently don't have VPC Endpoint Services available for certain services used by HTC-Grid. This means that at this stage HTC-Grid can not be deployed in these regions. Below is the list of tested regions where we encountered this issue:
* eu-north-1
