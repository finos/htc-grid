+++
title = "Task Lifecycle"
weight = 30
+++


## HTC-Grid Task Lifecycle

{{< img "htc-high-level-arch.png" "High Level Architecture" >}}


1.	A client task (comprising of task definition and task payload) is submitted via the **HTC Grid Connector Library** (abbrev. GCL).
1.	Each **task payload** - the data associated with the task that needs to be passed to the execution process – is loaded to the **Data Plane**.
1.	Each task **definition** - a JSON record that contains meta-data that defines how to schedule the task and client’s supplied commands that define how to launch the task – is loaded to the **Control Plane**:

    a)	The task definition is registered with the Control-Plane (Amazon DynamoDB).

    b)	The task definition is placed on the Control-Plane queue (Amazon SQS).


1.	Each idle **HTC-Grid Agent** pulls a task from the **Control-Plane** queue.
1.	The agent retrieves the corresponding task’s payload from the **Data-Plane** and commence calculation – the task invoked as a local lambda in the collocated lambda container.
1.	Upon completion the agents write the result the **Data-Plane**.
1.	Throughout the task process life-cycle each host agent maintains a status heart-beat with the DynamoDB registered task.
1.	The GCL is notified upon task completion.
1.	Upon notification the GCL pulls the results from the Data-Plane, returning these to the client.



HTC-Grid allows client applications to submit a session (job) containing a single task, or a vector of tasks. Each submission generates a system-wide unique session_id which is associated with the submission, the session_id is returned to the client application. Successful reception of a session_id indicates that all the tasks of the job are in the system and eventually will be executed.

Client applications can use session_id to inquire the state of the tasks within the session (e.g., pending, running, failed, completed, etc.) and subsequently retrieve results once all the tasks of the session are completed. A session is considered to be completed once all tasks of the session are completed. Additionally, if the session did not complete within specified timeout, the session is considered to be failed.

During a normal usage, client application would either (i) save the returned session object locally and submit more sessions (jobs) (in case of a batch of jobs) or will wait for the completion of the last submitted session. Note, each session can have a list of tasks associated with it. A multi session submission is also possible, in that case a list of session IDs is returned by the connection object.


## HTC-Grid Task's State Transition Diagram

{{< img "htc-tasks-state-transition-diagram.png" "State Transition" >}}

{{< img "htc-tasks-state-transition-table.png" "State Transition" >}}
