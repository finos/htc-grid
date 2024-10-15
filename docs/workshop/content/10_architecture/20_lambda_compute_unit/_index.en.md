+++
title = "Lambda as a Unit of Compute"
weight = 20
+++


{{% notice note %}}
We refer to Lambda as a unit of compute instead of **[AWS Lambda](https://aws.amazon.com/lambda/)**, the service that allows you to run lambdas. In this section we explain how HTC-Grid integrates the environment to execute units of compute that look to all effects like a lambda, but that allow to select which compute plane you want to execute them on, with the current implementation done for EKS. 
{{% /notice %}}

One of the main Tenets as we described earlier on is making the system modular. When looking at how the worker side of the architecture would invoke the execution we had to consider:

* The worker could invoke the execution of different programs, in different programming languages
* The interface for execution of the library on the agent should be simple, and provide a level of familiarity to Grid users.
* The deployment mechanism should be able to run in multiple Compute Planes, as different users may want different compute planes such as: [Amazon Elastic Kubernetes Service (EKS)](https://aws.amazon.com/eks), [Amazon Elastic Container Servie (ECS)](https://aws.amazon.com/ecs/), [AWS Lambda](https://aws.amazon.com/lambda/), [Amazon EC2 Instances (EC2)](https://aws.amazon.com/ec2/), [AWS Batch](https://aws.amazon.com/batch/), etc.)

{{< img "Lambda-as-a-compute-unit.png" "Lambda as a compute unit" >}}

We selected the Lambda interface as a main unit of compute. The release of [AWS Lambda Container Image Support](https://aws.amazon.com/blogs/aws/new-for-aws-lambda-container-image-support/) allows us then to use the minimum deployable unit of a lambda within a container, and thus meet the tenets for the project.


To simplify: 
* The programming interface of the HTC-Grid worker code looks like a lambda.
* The deployment of the code follows all the best practices for containers

For example for python code the entry-point for the worker functionality looks like the following code snippet where the event will be a copy of the data for the task and the context provides contextual information about the session and task. Other programming languages follow a similar approach ([you can read more about those here](https://docs.aws.amazon.com/lambda/latest/dg/lambda-samples.html)):

```python
def handler_name(event, context): 
    ...
    return some_value
```

Within the EKS implementation that the project uses by default, the agent provides a connectivity layer between the HTC-Grid and the Lambda container. The Agent pulls new tasks from the task queues in the Control Plane, once a new task is acquired the agent invokes the Lambda container and passes the task definition and payload. The Lambda container contains custom executable that performs the work.  The following diagram depicts how the HTC-Agent integrates in EKS with the Lambda container. HTC-Agent container runs in the same pod as the Lambda container. The lambda container exposes an HTTP interface on the `localhost` so that only the the HTC-Agent container can access the endpoint.

{{< img "eks_lambda_implementation.png" "Lambda and HTC-Agent" >}}


{{% notice info %}}
At time of writing this, the project is undergoing changes to move from **[lambci](https://github.com/lambci/lambci)** to the **[aws-lambda-runtime-interface-emulator](https://github.com/aws/aws-lambda-runtime-interface-emulator)**. *aws-lambda-runtime-interface-emulator* is an AWS project that simplifies the integration, reduce the code needed and allows us to provide the lambda simulation integrated with other architecture, enabling us in the future to support **[Graviton](https://aws.amazon.com/ec2/graviton/)** instances.
{{% /notice %}}
