---
title: "Container Insights"
chapter: false
weight: 30
---

HTC-Grid deploys fluent-bit and Cloudwatch agents as a [Kubernetes DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/) thus enabling [CloudWatch Container Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html).

Container Insights  collects, aggregates, and summarizes metrics and logs from HTC-Grid. So far we have submitted a session with a single task to the system. Let's find out the logs from the Agent where the `session_id` was used, and check which is the session ID of our service

1. In the AWS Console, select **Cloudwatch** and on the left hand menu, select  **Logs** /**Logs Insights**.

1. In the Select group box, select **/aws/eks/htc-main/aws-fluentbit-logs**. Then in the edit box add the query below and then run the query

```text
fields @timestamp, @message
| filter @message like /session_id/
| sort @timestamp desc
| limit 20
```

That will show at least 3 log entries that had *session_id* on them for the HTC-Agent. One created when the HTC-Agent picked up the task from SQS, another one prior to execution and a final one upon termination.

{{< img "container_insights_log_insights.png" "container_insights_log_insights" >}}

From those logs we get that the session we created was `f49ec086-f948-11eb-9ced-9ad2c34ef49d-part001`, the same mechanism can be used to understand which nodes and agents executed specific tasks.

{{% notice tip %}}
Logs are not the only data collected by Container Insights. Check out in the **Container Insights** metrics, what kind of metrics would be useful to manage your applications.
{{% /notice %}}
