+++
title = "Control Plane"
weight = 60
+++


The control plane Is responsible for queuing and scheduling tasks submitted by each client for the execution on the next available computational slot; and retrying tasks that fail. The client GCL invokes a submit_task Lambda function via an HTTPS request. The submit_task Lambda iterates over the list of submitted tasks (all tasks in the session) and creates:

1.	A single row in the DynamoDB state table per task .
1.	a corresponding entry in SQS.

{{% notice note %}}
The insertions sequence is important to avoid race condition. As shown in the following DynamoDB table extract, each row contains a set of attributes associated with the task’s definition.
{{% /notice %}}

On insertion into DynamoDB, a task record’s initial status is set to pending. The DynamoDB state table maintains two global secondary indexes (GSI): 

1. session_id + task_status GSI is used to access tasks within each unique session.id 
1. task_status + heartbeat_expiration_timestamp GSI is used to retrieve running tasks with expired heartbeats. 

These session state tables define the single source of truth for each instance of the service. After recording task status, the submit_tasks lambda puts a copy of the task’s definition into the SQS queue, upon which they become available for execution. Each Agent runs an event loop to check for tasks in the designated SQS queue. The next available task is pulled and the task’s status updated to running. Upon completion, the Agent changes the task status to finished. As standard SQS queue (not FIFO) is used, message reordering can occur, and while more than once delivery may (very infrequently) occur, the scheduler reconciles such duplicates. 

{{< img "control-plane.png"  "HTC-control-plane" >}}
