+++
title = "High Level Architecture"
weight = 10
+++


## High Level Architecture

{{< img "htc-high-level-arch.png" "High Level Architecture" >}}


HTC-Grid has been designed with strong focus on the following tenets: use of cloud native serverless and fully managed services, performance & scalability, availability, cost optimisation, and operational simplicity.

The grid system is composed of 4 functional components:
* **HTC-Grid Connector Library**: A language specific API that provides an entry point for Client Applications to interact with the grid.
* **Data Plane**: Provides a channel to store submitting jobs’ definitions and payload and retrieving computational results, it is intended to be configurable so different workloads can use their preferred Data Plane channel/service based on the workload needs
* **Control Plane**: This is the equivalent to the scheduler component. It keeps track of the task's execution, grid scaling and error handling.
* **Compute Plane**: Provides a pool of Computing Resources that perform computational tasks.

{{% notice warning %}}
At the moment HTC-Grid Compute plane does only provide an EKS Implementation. The intent of the HTC-Agent that runs on the compute plane is that it can be migrated to support other compute planes
{{% /notice %}}

Inter module communication is implemented using standardized AWS APIs which facilitates independent development and provide further customization options.

Internally, each of the 4 functional components (API, Data & Control Planes, and Compute Resources) are built using exclusively cloud native building blocks such as: serverless functions and fully managed services. These blocks require no human maintenance (zero administration), are highly available by design, and can scale horizontally in response to demand.

