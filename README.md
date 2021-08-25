# HTC-Grid  
The high throughput compute grid project (HTC-Grid) is a container based cloud native HPC/Grid environment. The project provides a reference architecture that can be used to build and adapt a modern High throughput compute solution using underlying AWS services, allowing users to submit high volumes of short and long running tasks and scaling environments dynamically.

**Warning**: This project is an Open Source (Apache 2.0 License), not a supported AWS Service offering.

### When should I use HTC-Grid ?
HTC-Grid should be used when the following criteria are meet:
1. A high task throughput is required (from 250 to 10,000+ tasks per second).
2. The tasks are loosely coupled.
3. Variable workloads (tasks with heterogeneous execution times) are expected and the solution needs to dynamically scale with the load.

### When should I not use the HTC-Grid ?
HTC-Grid might not be the best choice if :
1. The required task throughput is below 250 tasks per second: Use [AWS Batch](https://aws.amazon.com/batch/) instead.
2. The tasks are tightly coupled, or use MPI. Consider using either [AWS Parallel Cluster](https://aws.amazon.com/hpc/parallelcluster/) or [AWS Batch Multi-Node workloads](https://docs.aws.amazon.com/batch/latest/userguide/multi-node-parallel-jobs.html) instead
3. The tasks uses third party licensed software.

### How do I use HTC-Grid ?

The full documentation of the HTC grid can be accessed here [https://awslabs.github.io/aws-htc-grid/](https://awslabs.github.io/aws-htc-grid/)


