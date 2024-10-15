---
title: "Building HTC-Grid Artifacts"
chapter: false
weight: 70
---

## Building HTC-Grid 

Before we proceed with the final step, we need to build a few HTC-Grid Artifacts. HTC artifacts include: python packages (for the HTC-Connector-Library), docker images (deploying example applications), configuration files for HTC and k8s. 

To build and install these:

```
make happy-path TAG=$TAG REGION=$HTCGRID_REGION
```

A few notes on this command:
 - If `TAG` is omitted then *mainline* will be chosen as the default value.
 - If `REGION` is omitted then eu-west-1 will be used.

 Once the command above gets executed, A folder named `generated` will be created at `~/environment/htc-grid/generated`. This folder will contain some important files, like the following:

* **grid_config.json**: A configuration file that contains the deployment settings for HTC-Grid.
* **single-task-test.yaml**:  A Kubernetes job that can be used to test the installation and submit a single task.
* **batch-task-test.yaml**:  A Kubernetes job that can be used to test the installation and submit multiple sessions of tasks.

## Configuring HTC-Grid Runtime

The `~/environment/htc-grid/generated/grid_config.json` file contains the configuration file that we will use to deploy HTC-Grid, let's explore a few sections:

#### Configuration of Data-plane and Control-Plane DynamoDB Read/Write Capacity Modes

{{< highlight json "linenos=table,linenostart=1" >}}
{
  "region": "eu-west-1",
  "project_name": "main",
  "grid_storage_service": "REDIS",
  "max_htc_agents": 100,
  "min_htc_agents": 1,
  "dynamodb_default_read_capacity": 10,
  "dynamodb_default_write_capacity": 10,
{{< / highlight >}}

* **grid_storage_service** : Is selecting [ElastiCache for Redis](https://aws.amazon.com/elasticache/redis/) as the HTC-Grid Data-plane
* **max_htc_agents**: Is the maximum number of HTC-Grid workers (HTC-Agents) that we allow in our system.
* **min_htc_agents**: Is the minimum number of HTC-Grid workers (HTC-Agents) that we want at all time in our system. Note you can configure later on actions to increase or decrease based time of the day, etc. This currently maps with Kubernetes HPA configuration when running on EKS
* **dynamodb_default_read_capacity** & **dynamodb_default_write_capacity** this two settings define and control the IO operations that dynamoDB support. Higher volumes of short running tasks need a higher write and read capacity. You can read more about DybamoDB capacity Modes [here](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/HowItWorks.ReadWriteCapacityMode.html)


#### Compute Plane Worker Configurations

Using EKS as the Compute Plane allows us to use EC2 Spot Instances. Amazon EC2 Spot Instances offer spare compute capacity available in the AWS cloud at steep discounts compared to On-Demand instances. Spot Instances enable you to optimize your costs on the AWS cloud and scale your application’s throughput up to 10X for the same budget.


Given that we will use Kubernetes [Cluster Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler) we create the following node groups each with instances of the same size. You can read more about [EKS and Spot best practices here](https://aws.amazon.com/blogs/compute/cost-optimization-and-resilience-eks-with-spot-instances/)

{{< highlight json "linenos=table,linenostart=9" >}}
  "eks_worker_groups": [
      {
        "node_group_name": "worker-small-spot",
        "instance_types" : ["m6i.xlarge", "m6id.xlarge", "m6a.xlarge", "m6in.xlarge", "m5.xlarge","m5d.xlarge","m5a.xlarge", "m5ad.xlarge", "m5n.xlarge"],
        "capacity_type"  : "SPOT",
        "min_size"       : 1,
        "max_size"       : 3,
        "desired_size"   : 1
      },
      {
        "node_group_name": "worker-medium-spot",
        "instance_types" : ["m6i.4xlarge", "m6id.4xlarge", "m6a.4xlarge", "m6in.4xlarge", "m5.4xlarge","m5d.4xlarge","m5a.4xlarge", "m5ad.4xlarge", "m5n.4xlarge"],
        "capacity_type"  : "SPOT",
        "min_size"       : 0,
        "max_size"       : 3,
        "desired_size"   : 0
      },
      {
         "node_group_name": "worker-large-spot",
         "instance_types" : ["m6i.8xlarge", "m6id.8xlarge", "m6a.8xlarge", "m6in.8xlarge", "m5.8xlarge","m5d.8xlarge","m5a.8xlarge", "m5ad.8xlarge", "m5n.8xlarge"],
         "capacity_type"  : "SPOT",
         "min_size"       : 0,
         "max_size"       : 3,
         "desired_size"   : 0
      }
  ],
{{< / highlight >}}



{{% notice note %}}
As this is a test deployment we will just use the default values. Users may need to scale this values up depending on your workload. When they do they will also need to consider the `max_htc_agents` and `min_htc_agents` as well as the `dynamodb_default_read_capacity` and `dynamodb_default_write_capacity
{{% /notice %}}


#### Configuring HTC-Agent configuration

Finally the last section of the file. We have highlighted a section that defines how much memory and CPU the deployment will get. In this case we have attributed ~1 VCPU amd ~2GB of Ram for each of the workers.

Note also how the location of the lambda points to the `lambda.zip` that we just created by executing the `make` command above.

{{< highlight json "linenos=table,hl_lines=1-10,linenostart=35" >}}
  "agent_configuration": {
    "lambda": {
      "minCPU"   : "800",
      "maxCPU"   : "900",
      "minMemory": "1200",
      "maxMemory": "1900",
      "location" : "s3://main-lambda-unit-htc-grid-0d7b1b70/lambda.zip",
      "runtime"  : "provided"
    }
  },
  "enable_private_subnet" : true,
  "vpc_cidr_block_public" : 24,
  "vpc_cidr_block_private": 18,
  "input_role": [
      {
        "rolearn" : "arn:aws:iam::XXXXXXXXXXXXXX:role/Admin",
        "username": "lambda",
        "groups"  : ["system:masters"]
      }
  ]
}
{{< / highlight >}}
