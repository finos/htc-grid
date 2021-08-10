+++
title = "Data Plane"
weight = 50
+++


{{< img "htc-grid-data-plane.png"  "HTC-data-plane" >}}

The data plane is designed to handle data transfer and can be used to pass any type of data necessary for the task’s execution (e.g., arguments to be passed to the executable, static libraries, etc.) and specific for a given task, and store task output. 

The persistence service may be used for the duration of the computation only, in which case caching implementation can work well, or could also be used to preserve historical data. HTC-Grid currently supports three implementations: 
* [Amazon Simple Cloud Storage (S3)](https://aws.amazon.com/s3/), 
* [Amazon ElastiCache for Redis](https://aws.amazon.com/elasticache/redis/) 
* and a S3-Redis Hybrid where Redis is used as a write-through cache. 

{{% notice note %}}
At the time of writing this, the team has been testing the integration of a Data plane plugin for **[Amazon FSx for Lustre](https://aws.amazon.com/fsx/lustre/)**, that will be added in the next release.
{{% /notice %}}


The data plane does not have a data retention mechanism – though S3 data lifecycle policies can be applied to reduce the cost. If the size of task payload is small (in the order of a few KB), this data embedded the task definition and the data-plane bypassed. Also, if required, large amounts of common input data can be preloaded into the data-plane prior to start of workload execution.