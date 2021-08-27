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
 - If `TAG` is omitted then mainline will be the chosen has a default value.
 - If `REGION` is omitted then eu-west-1 will be used.

 Once the command above gets executed, A folder named `generated` will be created at `~/environment/aws-htc-grid/generated`. This folder should contain the following two important files:

* **grid_config.json**: A configuration file for the grid with basic setting
* **single-task-test.yaml**:  A kubernetes job that can be used to test the installation and submit a single task.

## Configuring HTC-Grid Runtime

The `~/environment/aws-htc-grid/generated/grid_config.json` file contains the configuration file that we will use to deploy HTC-Grid, let's explore a few sections:

#### Configuration of Data-plane and Control-Plane DynamoDB Read/Write Capacity Modes

{{< highlight json "linenos=table,linenostart=1" >}}
{
  "region": "eu-west-1",
  "project_name": "main",
  "grid_storage_service" : "REDIS",
  "max_htc_agents": 100,
  "min_htc_agents": 1,
  "dynamodb_default_read_capacity" : 10,
  "dynamodb_default_write_capacity" : 10,
{{< / highlight >}}

* **grid_storage_service** : Is selecting [ElastiCache for Redis](https://aws.amazon.com/elasticache/redis/) as the HTC-Grid Data-plane
* **max_htc_agents**: Is the maximum number of HTC-Grid workers (HTC-Agents) that we allow in our system.
* **min_htc_agents**: Is the minimum number of HTC-Grid workers (HTC-Agents) that we want at all time in our system. Note you can configure later on actions to increase or decrease based time of the day, etc. This currently maps with Kubernetes HPA configuration when running on EKS
* **dynamodb_default_read_capacity** & **dynamodb_default_write_capacity** this two settings define and control the IO operations that dynamoDB support. Higher volumes of short running tasks need a higher write and read capacity. You can read more about DybamoDB capacity Modes [here](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/HowItWorks.ReadWriteCapacityMode.html)


#### Compute Plane Worker Configurations

Using EKS as the Compute Plane allows us to use EC2 Spot Instances. Amazon EC2 Spot Instances offer spare compute capacity available in the AWS cloud at steep discounts compared to On-Demand instances. Spot Instances enable you to optimize your costs on the AWS cloud and scale your application’s throughput up to 10X for the same budget.


Given that we will use Kubernetes [Cluster Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler) we create two node groups each with instances of the same size. You can read more about [EKS and Spot best practices here](https://aws.amazon.com/blogs/compute/cost-optimization-and-resilience-eks-with-spot-instances/)

{{< highlight json "linenos=table,linenostart=9" >}}
  "eks_worker_groups" : [
      {
        "name"                    : "worker-small-spot",
        "override_instance_types" : ["m5.xlarge","m4.xlarge","m5d.xlarge","m5a.xlarge"],
        "spot_instance_pools"     : 0,
        "asg_min_size"            : 0,
        "asg_max_size"            : 3,
        "asg_desired_capacity"    : 1,
        "on_demand_base_capacity" : 0
      },
      {
        "name"                    : "worker-medium-spot",
        "override_instance_types" : ["m5.2xlarge","m5d.2xlarge", "m5a.2xlarge","m4.2xlarge"],
        "spot_instance_pools"     : 0,
        "asg_min_size"            : 0,
        "asg_max_size"            : 3,
        "asg_desired_capacity"    : 0,
        "on_demand_base_capacity" : 0

      }
  ],
{{< / highlight >}}



{{% notice note %}}
As this is a test deployment we will just use the default values. Users may need to scale this values up depending on your workload. When they do they will also need to consider the `max_htc_agents` and `min_htc_agents` as well as the `dynamodb_default_read_capacity` and `dynamodb_default_write_capacity
{{% /notice %}}


#### Configuring HTC-Agent configuration

Finally the last section of the file. We have highlighted a section that defines how much memory and CPU the deployment will get. In this case we have attributed ~1 VCPU amd ~2GB of Ram for each of the workers.

Note also how the location of the lambda points to the `lambda.zip` that we just created by executing the `make` command above.

{{< highlight json "linenos=table,hl_lines=1-10,linenostart=30" >}}
  "agent_configuration": {
    "lambda": {
      "minCPU": "800",
      "maxCPU": "900",
      "minMemory": "1200",
      "maxMemory": "1900",
      "location" : "s3://main-lambda-unit-htc-grid-2b8838c8eecc/lambda.zip",
      "runtime": "provided"
    }
  },
  "enable_private_subnet" : true,
  "vpc_cidr_block_public" :["10.0.192.0/24", "10.0.193.0/24", "10.0.194.0/24"],
  "vpc_cidr_block_private" :["10.0.0.0/18","10.0.64.0/18", "10.0.128.0/18"],
  "input_role":[
      {
        "rolearn"  : "arn:aws:iam::021436251583:role/Admin",
        "username" : "lambda",
        "groups"   : ["system:masters"]
      }
  ]
}
{{< / highlight >}}




