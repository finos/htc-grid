# Cleanup and Resource Management

This guide covers how to properly clean up HTC-Grid resources to avoid unnecessary costs.

!!! warning "Important"
    If you're attending an AWS event, you can skip this section as resources will be automatically cleaned up. However, we recommend reading through to understand the cleanup process.

## Complete Cleanup Process

### 1. Destroy HTC-Grid Deployment

Remove all HTC-Grid infrastructure and cached modules:

```bash
make auto-destroy-python-runtime TAG=$TAG REGION=$HTCGRID_REGION
make reset-grid-deployment TAG=$TAG REGION=$HTCGRID_REGION
```

!!! note "Timeout Handling"
    Resource destruction may take time. If you encounter timeout errors, re-run the commands - Terraform will track remaining resources and continue cleanup.

### 2. Clean Up ECR Images

Remove container images and repositories:

```bash
make auto-destroy-images TAG=$TAG REGION=$HTCGRID_REGION
make reset-images-deployment TAG=$TAG REGION=$HTCGRID_REGION
```

### 3. Remove S3 State Buckets

!!! danger "Final Step Only"
    Only perform this step after all other cleanup is complete. These buckets contain Terraform state - removing them will cause Terraform to lose track of your deployment state.

```bash
make delete-grid-state TAG=$TAG REGION=$HTCGRID_REGION
```

## Partial Cleanup Options

### Scale Down Without Destroying

To reduce costs while keeping the infrastructure:

```bash
# Scale EKS nodes to zero
kubectl scale deployment htc-agent --replicas=0

# Update node group to minimum size
aws eks update-nodegroup-config \
  --cluster-name htc-grid-$TAG \
  --nodegroup-name htc-workers \
  --scaling-config minSize=0,maxSize=0,desiredSize=0
```

### Pause Specific Components

**Stop Task Processing:**
```bash
# Pause SQS message processing
kubectl scale deployment htc-agent --replicas=0
```

**Reduce Compute Capacity:**
```bash
# Scale down worker nodes
eksctl scale nodegroup --cluster=htc-grid-$TAG --name=htc-workers --nodes=0
```

## Verification Steps

### Check Resource Cleanup

**Verify EKS Cluster Removal:**
```bash
aws eks list-clusters --region $HTCGRID_REGION
```

**Verify ECR Repository Cleanup:**
```bash
aws ecr describe-repositories --region $HTCGRID_REGION
```

**Verify S3 Bucket Removal:**
```bash
aws s3 ls | grep $TAG
```

**Check CloudFormation Stacks:**
```bash
aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --region $HTCGRID_REGION \
  --query 'StackSummaries[?contains(StackName, `'$TAG'`)].StackName'
```

### Cost Verification

**Check for Remaining Resources:**
```bash
# List EC2 instances
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*$TAG*" \
  --query 'Reservations[].Instances[].{ID:InstanceId,State:State.Name}'

# List Load Balancers
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(LoadBalancerName, `'$TAG'`)].LoadBalancerName'

# List NAT Gateways
aws ec2 describe-nat-gateways \
  --filter "Name=tag:Name,Values=*$TAG*" \
  --query 'NatGateways[].{ID:NatGatewayId,State:State}'
```

## Troubleshooting Cleanup Issues

### Common Cleanup Problems

**EKS Cluster Won't Delete:**
```bash
# Force delete stuck resources
kubectl delete all --all --force --grace-period=0

# Delete finalizers if needed
kubectl patch deployment htc-agent -p '{"metadata":{"finalizers":null}}'
```

**ECR Repository Deletion Fails:**
```bash
# Force delete images first
aws ecr batch-delete-image \
  --repository-name htc-grid-$TAG \
  --image-ids imageTag=latest

# Then delete repository
aws ecr delete-repository --repository-name htc-grid-$TAG --force
```

**S3 Bucket Not Empty:**
```bash
# Empty bucket contents
aws s3 rm s3://$TAG-htc-grid-lambda-layer --recursive
aws s3 rm s3://$TAG-htc-grid-tfstate --recursive
aws s3 rm s3://$TAG-htc-grid-image-tfstate --recursive
```

**VPC Dependencies:**
```bash
# Check for remaining ENIs
aws ec2 describe-network-interfaces \
  --filters "Name=vpc-id,Values=vpc-xxxxx" \
  --query 'NetworkInterfaces[].NetworkInterfaceId'

# Delete stuck security groups
aws ec2 delete-security-group --group-id sg-xxxxx
```

### Manual Resource Cleanup

If automated cleanup fails, manually remove resources in this order:

1. **EKS Workloads:**
   ```bash
   kubectl delete all --all
   kubectl delete pvc --all
   kubectl delete pv --all
   ```

2. **Load Balancers:**
   ```bash
   aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerArn' | \
   xargs -I {} aws elbv2 delete-load-balancer --load-balancer-arn {}
   ```

3. **EKS Cluster:**
   ```bash
   eksctl delete cluster --name htc-grid-$TAG --region $HTCGRID_REGION
   ```

4. **VPC Resources:**
   ```bash
   # Delete in order: Subnets, Route Tables, Internet Gateway, VPC
   aws ec2 delete-vpc --vpc-id vpc-xxxxx
   ```

## Cost Monitoring

### Set Up Billing Alerts

```bash
# Create billing alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "HTC-Grid-Cost-Alert" \
  --alarm-description "Alert when HTC-Grid costs exceed threshold" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --threshold 100 \
  --comparison-operator GreaterThanThreshold
```

### Regular Cost Checks

```bash
# Check current month costs
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

## Best Practices

### Before Deployment
- Set up cost alerts and budgets
- Tag all resources with project identifiers
- Document cleanup procedures

### During Use
- Monitor resource utilization regularly
- Scale down during inactive periods
- Use spot instances where appropriate

### After Use
- Follow complete cleanup procedure
- Verify all resources are removed
- Check final billing to confirm cleanup

## Emergency Cleanup

If you need to quickly stop all charges:

```bash
# Emergency stop script
#!/bin/bash
TAG=${1:-main}
REGION=${2:-us-east-1}

echo "Emergency cleanup for TAG=$TAG in REGION=$REGION"

# Stop all EKS workloads
kubectl scale deployment --all --replicas=0

# Delete EKS cluster
eksctl delete cluster --name htc-grid-$TAG --region $REGION --wait

# Delete CloudFormation stacks
aws cloudformation delete-stack --stack-name $TAG --region $REGION

echo "Emergency cleanup initiated. Monitor AWS console for completion."
```

For additional help, see [Troubleshooting Guide](./troubleshooting.md) or contact support.
