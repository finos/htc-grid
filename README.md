# HTC-Grid
The high throughput compute grid project (HTC-Grid) is a container based cloud native HPC/Grid environment. The project provides a reference architecture that can be used to build and adapt a modern High throughput compute solution allowing users to submit high volumes of short and long running tasks and scaling environments dynamically.

**Warning**: This project is an Open Source (Apache 2.0 License).

### When should I use HTC-Grid ?
HTC-Grid should be used when the following criteria are meet:
1. A high task throughput is required (from 250 to 30,000+ tasks per second).
2. The tasks are loosely coupled.
3. Variable workloads (tasks with heterogeneous execution times) are expected and the solution needs to dynamically scale with the load.

### When should I not use the HTC-Grid ?
HTC-Grid might not be the best choice if :
1. The required task throughput is below 250 tasks per second.
2. The tasks are tightly coupled, or use MPI.
3. The tasks uses third party licensed software.

### How do I use HTC-Grid ?

The full documentation of the HTC grid can be accessed here [https://awslabs.github.io/aws-htc-grid/](https://awslabs.github.io/aws-htc-grid/)


