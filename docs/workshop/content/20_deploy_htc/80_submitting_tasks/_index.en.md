---
title: "Submitting Test Tasks"
chapter: false
weight: 90
---

Great! HTC-Grid has been deployed and now we can run a few tasks. The default installation of HTC-Grid comes with a [python test client application](https://github.com/finos/htc-grid/blob/main/examples/client/python/client.py) that runs a [C++ test worker](https://github.com/finos/htc-grid/tree/main/examples/workloads/c%2B%2B/mock_computation).

Before we exectute the job, let's to the following, on your IDE, open two more terminals.

{{< img "cloud9_open_terminal.png" "Cloud9 Open Terminal" >}}

If you recall from the architecture section, each of the workers is deployed within a Kubernetes Pod. There are two containers running on the pod: One is the HTC-Agent, in charge of processing the signals from the Control Plane. The second is the local lambda within the pod that runs the actual workload.

{{< img "eks_lambda_implementation.png" "EKS Lambda Implementation" >}}

We are going to stream the logs of each of the components. As you check in the previous section, there is one single HTC-Agent running. We will submit a single test task and stream the logs that each section does. In one of the new terminals type the following command.
```
kubectl logs deployment/htc-agent -c agent -f --tail 5
```

This shows the htc-agent logs. Note how there is a poll to request for new SQS tasks every few seconds.  In the other newly open terminal type the following command.

```
kubectl logs deployment/htc-agent -c lambda -f --tail 5
```
At this state this shouldn't be doing much, the lambda container is waiting to be invoked upon task submissions, so far it should only say something like `Lambda API listening on port 9001`. Note that por is only open on `localhost` and can only be accessed by the HTC-Agent.

### Submitting a Single Task

We are ready now to submit a single task. To simplify the execution, HTC-Grid deployment has also created a container image that can be deployed to act as a client so that you can run it directly as a [Kubernetes Job](https://kubernetes.io/docs/concepts/workloads/controllers/job/)

Two out of three of the Cloud9 terminals should be now showing logs (You can stop that process at anytime using `Ctrl-C`). Go to the terminal that is not displaying logs and run the following command:

```
cd ~/environment/htc-grid
kubectl apply -f ~/environment/htc-grid/generated/single-task-test.yaml
```

That will create a new Kubernetes job named `single-task`. You can also check the client logs created by the single task by running the following command:

```
kubectl logs job/single-task -f
```

{{% notice note %}}
It may take a few seconds for the single-job to be deployed to the kubernetes cluster. During that time the `kubectl logs` command may fail with an error similar to the error below. It only take a few seconds to start the container so, hust re-run the command and you should get the logs. `Error from server (BadRequest): container "generator" in pod "single-task-vch74" is waiting to start: ContainerCreating`.
{{% /notice %}}

To check the execution went as expected, check the output of of the `job/single-task` it should complete in a few seconds (~4 seconds).

The Lambda execution should now show an output similar to the one below:

{{< img "lambda_output_example.png" "lambda_output_example" >}}

As for the agent, you may need to scroll up on the terminal, but there should be one entry similar to the one below:

{{< img "htc_agent_output_example.png" "htc_agent_output_example" >}}

Finally there is one more place that we can check how our execution went **DynamoDB**. In the AWS Console, search for the AWS DynamoDB service.

1. In the AWS Console, search for the AWS DynamoDB service. Select **Tables** and then click on the table **htc_tasks_state_table-main**. When the selection comes up, click onthe **Items** tab.

  {{< img "dynamo_db_selection.png" "dynamo_db_selection." >}}

1. At this stage there is only one task submitted, just click on the task to see the internal representation of the task.

  {{< img "dynamodb_task_definition.png" "dynamodb_task_definition" >}}

If you want to re-run the job, you will need first to delete the kubernetes execution of the previous job, you can do that by running the following command:

```
cd ~/environment/htc-grid
kubectl delete -f ~/environment/htc-grid/generated/single-task-test.yaml
```
