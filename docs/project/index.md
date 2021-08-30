# HTC-Grid
The high throughput compute grid project (HTC-Grid) is a container based cloud native HPC/Grid environment. The project provides a reference architecture that can be used to build and adapt a modern High throughput compute solution using underlying AWS services, allowing users to submit high volumes of short and long running tasks and scaling environments dynamically.

**Warning**: This project is an Open Source (Apache 2.0 License), not a supported AWS Service offering.

### When should I use HTC-Grid ?
HTC-Grid should be used when the following criteria are meet:

* high task throughput is required (from 250 to 10,000+ tasks per second).
* The tasks are loosely coupled. 
* Variable workloads (tasks with heterogeneous execution times) are expected and the solution needs to dynamically scale with the load.

### When should I not use the HTC-Grid ?
HTC-Grid might not be the best choice if :

* The required task throughput is below 250 tasks per second: Use [AWS Batch](https://aws.amazon.com/batch/) instead. 
* The tasks are tightly coupled, or use MPI. Consider using either [AWS Parallel Cluster](https://aws.amazon.com/hpc/parallelcluster/) or [AWS Batch Multi-Node workloads](https://docs.aws.amazon.com/batch/latest/userguide/multi-node-parallel-jobs.html) instead 
* The tasks uses third party licensed software.

### How do I use HTC-Grid
If you want to use the HTC-Grid, please visit the following pages:

* [Getting Started](./getting_started/prerequisite.md)
* [User Guide](./user_guide/creating_your_a_client.md)
* [Developer Guide](./api/index.md) 
* [The workshop](https://main.d5fll76yf0v34.amplifyapp.com/)

