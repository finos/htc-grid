# Developing a Worker Function


HTC-Grid uses Amazon Elastic Kubernetes Service (Amazon EKS) as a computational back-end. Each engine is a pod running two containers: (i) an Agent and a (ii) Worker Function.

- The **Agent** provides a connectivity layer between the HTC-Grid and the Worker container. Agent's responsibilities include: (i) pulling for new tasks, (ii) interacting with the Data Plane (I/O), (iii) sending heartbeats back to Control Plane, and (iv) indicating completion of a task. Note, Agent does not need to be changed when developing new applications on HTC-Grid.
- The **Worker container** executes the custom code that performs the computational task. The execution is done locally within the container. The code of the worker function needs to be modified during the development.
    - Note: depending on the workload it is possible for the Worker function to access HTC-Grid's Data Plane directly or to access any other external systems as might be required. This functionality is not provided as part of the HTC-Grid.

At the high level the development process involves 4 steps:

1. Write a custom Worker code for the target workload.
2. Package all the dependencies into a docker container which also includes custom Lambda runtime that will be used to execute worker function.
3. Use this container to compile & test your code
4. Zip the compiled function along with any dependencies and upload to an S3 bucket (default bucket name is stored in $S3_LAMBDA_HTCGRID_BUCKET_NAME)
    1. (if S3 bucket is different from $S3_LAMBDA_HTCGRID_BUCKET_NAME) Update HTC-Grid configuration to point to the new location of the target Zip file.
