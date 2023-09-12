---
title: "Submitting multiple sessions"
chapter: false
weight: 30
---

So far we have explored a few ways to monitor the cluster, find logs in CloudWatch or stream them from the nodes directly. In this section we are going to submit a batch of tasks. 

### Submitting the multi-session job

Similar to before, we are now going to create a new Kubernetes job, which in this case will generate a total of 10 sessions, with 100 tasks each, where each task should take around 2 seconds to complete. Run the following command:

```
cd ~/environment/aws-htc-grid
kubectl apply -f ~/environment/aws-htc-grid/generated/batch-task-test.yaml
```

Like in the previous run, we can check what the application is doing by streaming the logs of the Kubernetes deployment.

```
kubectl logs job/batch-task -f 
```

{{% notice note %}}
It may take a few seconds for the single-job to be deployed to the kubernetes cluster. During that time the `kubectl logs` command may fail with an error similar to the error below. It only take a few seconds to start the container so, must re-run the command and you should get the logs. `Error from server (BadRequest): container "generator" in pod "single-task-vch74" is waiting to start: ContainerCreating`. 
{{% /notice %}}

### Dynamic Scaling 

This time it will take longer for the command to complete. The client should complete in ~5 minutes. In the background we will check how the Cluster will scale the number of workers and the number of instances.

{{% notice note %}}
The repository contains a helper script which can be used to monitor the progress and health of your batch job. It can be run using the command below (replacing the values for the correct `$HTC_NAMESPACE` and `$HTC_JOB_NAME`).
Running this script will give you an output as below, allowing you to track the progress of the job (the script updates in 30 second intervals) and show you the scale of your HPA (more below), deployment, nodes and job completion time and status.
{{% /notice %}}

```
export $HTC_NAMESPACE="default"
export $HTC_JOB_NAME="batch-task"
~/environment/aws-htc-grid/deployment/grid/scripts/shell/watch_htc.sh $HTC_NAMESPACE $HTC_JOB_NAME

=================================================================================================================================================
|                 Date | HPA (Desired/Max [Targets]) | Deployment (Ready/Total) | Nodes (Ready [NotReady/Total]) | Job (Completions [Duration]) |
=================================================================================================================================================
| 2023-08-11T12:41:13Z |                 1/100 [0/2] |                      1/1 |                        3 [0/3] |                    0/1 [22s] |
| 2023-08-11T12:41:46Z |                 1/100 [0/2] |                      1/1 |                        3 [0/3] |                    0/1 [55s] |
| 2023-08-11T12:42:19Z |           4/100 [246750m/2] |                      4/8 |                        3 [0/3] |                    0/1 [87s] |
| 2023-08-11T12:42:51Z |           16/100 [61688m/2] |                     4/32 |                        3 [1/4] |                     0/1 [2m] |
| 2023-08-11T12:43:24Z |           64/100 [14844m/2] |                    4/100 |                        4 [0/4] |                  0/1 [2m33s] |
| 2023-08-11T12:43:57Z |           100/100 [9500m/2] |                   43/100 |                        6 [0/6] |                   0/1 [3m6s] |
| 2023-08-11T12:44:30Z |           100/100 [8610m/2] |                   72/100 |                        7 [0/7] |                  0/1 [3m39s] |
| 2023-08-11T12:45:03Z |           100/100 [8610m/2] |                  100/100 |                        7 [0/7] |                  0/1 [4m11s] |
| 2023-08-11T12:45:35Z |           100/100 [1150m/2] |                  100/100 |                        7 [0/7] |                  1/1 [4m16s] |
```

In the architecture section we did mention that the **Horizontal Pod Autoscaler** would be in charge of scaling up the number of pods. We can review the HPA activity by running the following command in a new terminal window:

```
kubectl get hpa -w
```

While it runs, we will see something similar in the output to the one below:

```text
NAME               REFERENCE              TARGETS          MINPODS   MAXPODS   REPLICAS   AGE
keda-hpa-htc-agent-scaling-metrics   Deployment/htc-agent   62125m/2 (avg)   1         100       8          4h57m
keda-hpa-htc-agent-scaling-metrics   Deployment/htc-agent   31063m/2 (avg)   1         100       16         4h57m
keda-hpa-htc-agent-scaling-metrics   Deployment/htc-agent   30500m/2 (avg)   1         100       32         4h57m
keda-hpa-htc-agent-scaling-metrics   Deployment/htc-agent   15250m/2 (avg)   1         100       64         4h57m
keda-hpa-htc-agent-scaling-metrics   Deployment/htc-agent   9760m/2 (avg)    1         100       100        4h58m
keda-hpa-htc-agent-scaling-metrics   Deployment/htc-agent   9360m/2 (avg)    1         100       100        4h58m
keda-hpa-htc-agent-scaling-metrics   Deployment/htc-agent   8630m/2 (avg)    1         100       100        4h59m
```

{{% notice note %}}
The command above for `kubectl get hpa -w` runs in watch mode. To stop it, similar to the commands that we've seen where we stream logs, we can use the `Ctrl-C` key combination.
{{% /notice %}}


The targets, is basically a metric that derives from the metrics that we previously captured in CloudWatch and that is driven by the number of pending tasks in SQS (divided by 2 in this case). Over time if this number is bigger than the current number of REPLICAS, the REPLICA number will keep increasing until it reaches the MAXPODS (Maximum number of workers).

Once the pending number of tasks goes below, the number of REPLICAS will come back to the MINPODS defined in this case as 1. While HPA defines how many workers are needed, [Cluster Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler) is in charge of scaling-out and scaling-in the cluster.

Cluster Autoscaler will look for pods that are pending because they cannot be allocated in new engines and will take that as a signal to select which node group (Auto Scaling Group) of instances to Scale-out. You can follow Cluster Autoscaler operations by reading the Scale-out and Scale-in operations on the logs with the following command:

```
kubectl logs -n kube-system deployment/cluster-autoscaler-aws-cluster-autoscaler --tail 10 -f
```

Remember, if you want to repeat the same exercise you will need to delete the current completed batch with the following command 

```
kubectl delete -f ~/environment/aws-htc-grid/generated/batch-task-test.yaml  
```

### Checking the dashboards

To check how the Scaling exercise has gone, you can re-visit a few of the dashboards that we have already explored in this section.

1. Example of Grafana dashboards

    {{< img "grafana_example.png" "grafana_example" >}}

1. CloudWatch

    {{< img "cloudwatch_example.png" "grafana_example" >}}

1. Auto Scaling Groups:  As a result of Cluster Autoscaler scaling up the cluster, you should be able to see an increase in the number of instances on the Auto Scaling Groups.  In the AWS Console go to **EC2** / **Auto Scaling Groups**. The `spot` worker groups originally only needed one instance, but during the sale up operation they will reach ~6 to 7 nodes.
