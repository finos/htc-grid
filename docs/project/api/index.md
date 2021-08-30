# Introduction
This section outlines how to develop and deploy a custom application on HTC-Grid.
At the top level, there are 3 main components that need to be developed:


1. A **client application(s)** that will interact with a deployment of HTC-Grid by submitting tasks and retrieving results.
2. A **worker (lambda) function** that will be receiving and executing tasks.
3. **Configuration of the HTC-Grid's deployment process** to incorporate all the relevant changes (specifically for the backend worker functions).

