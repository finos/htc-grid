+++
title = "HTC-AWS-Grid"
chapter = false
weight = 10
+++

# AWS-HTC-Grid

{{% notice warning %}}
**Warning:** This is an Open Source (Apache 2.0 License) project and NOT a supported AWS Service offering.
{{% /notice %}}

The high throughput compute grid project (HTC-Grid) is a container based cloud native HPC/Grid environment. The project provides a reference architecture that can be used to build and adapt a modern High throughput compute solution using underlying AWS services, allowing users to submit high volumes of short and long running tasks and scaling environments dynamically.

## When should I use HTC-Grid?
HTC-Grid should be used when the following criteria are met:

* A high task throughput is required (from 250 to 10,000+ tasks per second). The tasks are loosely coupled.
* Variable workloads (tasks with heterogeneous execution times) are expected and the solution needs to dynamically scale with the load.


## When should I not use the HTC-Grid?
HTC-Grid might not be the best choice if:

* The required task throughput is below 250 tasks per second: Use **[AWS Batch](https://aws.amazon.com/batch/)** instead.
* The tasks are tightly coupled, or use MPI. Consider using either **[AWS Parallel Cluster](https://aws.amazon.com/hpc/parallelcluster/)** or **[AWS Batch Multi-Node](https://docs.aws.amazon.com/batch/latest/userguide/multi-node-parallel-jobs.html)** workloads instead.
* The tasks use third party licensed software.