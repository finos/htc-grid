# Monitoring HTC-Grid

This guide covers monitoring HTC-Grid using Amazon CloudWatch, Prometheus, and Grafana, including log analysis with CloudWatch Container Insights.

## Overview

HTC-Grid provides multiple monitoring approaches:

- **Amazon CloudWatch** - Native AWS monitoring and dashboards
- **Prometheus & Grafana** - Advanced metrics and visualization
- **CloudWatch Container Insights** - EKS cluster and container monitoring
- **Application Logs** - Real-time log streaming and analysis

## CloudWatch Monitoring

### Basic CloudWatch Dashboard

Create a custom dashboard to monitor key metrics:

1. **Go to CloudWatch Console** → Dashboards → Create Dashboard
2. **Add widgets for key metrics:**
   - SQS queue depth and message rates
   - Lambda invocation counts and durations
   - DynamoDB read/write capacity and throttling
   - EKS cluster resource utilization

### Key Metrics to Monitor

**SQS Metrics:**
- `ApproximateNumberOfMessages` - Tasks waiting in queue
- `NumberOfMessagesSent` - Task submission rate
- `NumberOfMessagesReceived` - Task processing rate

**Lambda Metrics:**
- `Invocations` - Task execution count
- `Duration` - Task execution time
- `Errors` - Failed task count
- `Throttles` - Resource constraint indicators

**DynamoDB Metrics:**
- `ConsumedReadCapacityUnits` - Read usage
- `ConsumedWriteCapacityUnits` - Write usage
- `ThrottledRequests` - Capacity issues

## Grafana and Prometheus

HTC-Grid deploys Grafana with Prometheus for advanced monitoring.

### Access Grafana Dashboard

1. **Get Grafana URL from deployment outputs:**
   ```bash
   cd deployment/grid/terraform
   terraform output grafana_url
   ```

2. **Login credentials:**
   - Username: `admin`
   - Password: The password you set during deployment

3. **Navigate to HTC-Grid dashboards:**
   - Cluster overview
   - Task execution metrics
   - Resource utilization
   - Performance trends

### Key Grafana Dashboards

**HTC-Grid Overview:**
- Real-time task throughput
- Queue depth trends
- Cluster scaling events
- Error rates and patterns

**Resource Monitoring:**
- CPU and memory utilization
- Network I/O patterns
- Storage usage
- Pod scaling metrics

## CloudWatch Container Insights

Container Insights provides detailed EKS monitoring.

### Enable Container Insights

If not already enabled during deployment:

```bash
# Enable Container Insights for your cluster
aws logs create-log-group --log-group-name /aws/containerinsights/htc-grid-$TAG/cluster
aws logs create-log-group --log-group-name /aws/containerinsights/htc-grid-$TAG/application
```

### Container Insights Features

**Performance Monitoring:**
- Node and pod resource usage
- Container-level metrics
- Network performance
- Storage I/O patterns

**Log Insights Queries:**

```sql
-- Find failed tasks
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 100

-- Monitor task processing times
fields @timestamp, @message
| filter @message like /Task completed/
| parse @message "duration: * ms" as duration
| stats avg(duration), max(duration), min(duration) by bin(5m)
```

## Real-time Log Monitoring

### Stream Component Logs

Monitor HTC-Grid components in real-time:

```bash
# HTC-Agent logs
kubectl logs deployment/htc-agent -c agent -f --tail 10

# Lambda container logs
kubectl logs deployment/htc-agent -c lambda -f --tail 10

# All pods in namespace
kubectl logs -f --all-containers=true --selector app=htc-agent
```

### Log Analysis Patterns

**Task Lifecycle Tracking:**
- Task submission: `Task received: task_id=xxx`
- Task start: `Executing task: task_id=xxx`
- Task completion: `Task completed: task_id=xxx, duration=xxx`
- Task failure: `Task failed: task_id=xxx, error=xxx`

**Performance Indicators:**
- Queue polling frequency
- Task processing latency
- Resource allocation events
- Scaling decisions

## Monitoring Task Execution

### Submit Test Workload for Monitoring

Create a test session with multiple tasks:

```bash
# Create multi-task test job
kubectl apply -f examples/submissions/k8s_jobs/multiple-tasks.yaml

# Monitor execution
kubectl logs job/multiple-tasks -f
```

### Monitor Scaling Behavior

Watch cluster scaling in response to load:

```bash
# Monitor node scaling
kubectl get nodes -w

# Monitor pod scaling
kubectl get pods -w

# Monitor HPA (if configured)
kubectl get hpa -w
```

## Performance Optimization

### Key Performance Indicators

**Throughput Metrics:**
- Tasks per second processed
- Queue processing rate
- End-to-end task latency

**Resource Efficiency:**
- CPU/Memory utilization per task
- Cost per task execution
- Resource waste indicators

**Scaling Effectiveness:**
- Scale-up response time
- Scale-down efficiency
- Resource allocation accuracy

### Optimization Strategies

**Queue Management:**
- Monitor queue depth trends
- Adjust worker pool sizes
- Optimize task batching

**Resource Allocation:**
- Right-size worker nodes
- Optimize container resource requests
- Configure appropriate scaling policies

## Alerting and Notifications

### CloudWatch Alarms

Set up alerts for critical conditions:

```bash
# High queue depth alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "HTC-Grid-High-Queue-Depth" \
  --alarm-description "Alert when queue depth is high" \
  --metric-name ApproximateNumberOfMessages \
  --namespace AWS/SQS \
  --statistic Average \
  --period 300 \
  --threshold 1000 \
  --comparison-operator GreaterThanThreshold

# High error rate alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "HTC-Grid-High-Error-Rate" \
  --alarm-description "Alert when error rate is high" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold
```

### Grafana Alerts

Configure Grafana alerts for:
- Task processing delays
- Resource exhaustion
- Cluster health issues
- Performance degradation

## Troubleshooting Common Issues

### High Queue Depth
- Check worker node availability
- Verify task processing efficiency
- Review scaling configuration

### Task Failures
- Examine task logs for errors
- Check resource constraints
- Validate input data format

### Performance Degradation
- Monitor resource utilization
- Check network connectivity
- Review scaling policies

## Best Practices

1. **Establish Baselines** - Monitor normal operation patterns
2. **Set Appropriate Thresholds** - Avoid alert fatigue
3. **Regular Review** - Analyze trends and optimize
4. **Capacity Planning** - Monitor growth patterns
5. **Cost Optimization** - Track resource efficiency

For more detailed troubleshooting, see [Troubleshooting Guide](./troubleshooting.md).
