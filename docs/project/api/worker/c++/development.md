# Developing C++ Worker Function

Writing a C++ Worker Function requires creation of an additional shell script: ``bootstrap``. The bootstrap script is a simple wrapper that takes inputs from Agent and passes it to the C++ executable, similarly it takes the response and passes it back to the Agent once task is done. See example below:

![ComputeEnvArchitecture](../../../images/developmentCpp.png)

An example of a complete ``bootstrap`` can be found here: ``examples/workloads/c++/mock_computation/bootstrap``, although, a custom version of the bootstrap script will be required for the custom Worker function.

- The bootstrap script takes task's definition as a string and passes them to the executable as an argument.
- C++ executable does not need to have a lambda_handler method implemented, instead, the execution starts at the ``main`` method.


## C++ Including Dependencies

Packaging all dependencies and uploading them to an S3 bucket is generally the same as for the Python3 runtime. However, C++ requires an additional step of compiling the source code before zipping all the dependencies. Compiling all the dependencies in the container guarantees that the executable will run in the provided runtime once deployed in HTC-Grid. Refer to a complete example here: ``examples/workloads/c++/mock_computation/Dockerfile.Build``

```Dockerfile
# Snippet example:
...

COPY mock_compute_engine.cpp .

COPY Makefile .  #Compile the executable in the runtime environment.

RUN make main
...
```

# 3. Configuring HTC-Grid Deployment

- There are no additional changes required to HTC-Grid to define/launch new Client applications.
- Some changes might be required to update Worker functions, see below

The root ./Makefile  has 3 options for building and uploading sample Worker functions (e.g., ``upload-c++``, ``upload-python``, and ``upload-python-ql``). These options simply automate all steps described in Section 2 "Developing a Worker Function". Follow these examples to build & upload custom worker function code. To execute each option in isolation, specify the option with the make (i.e., instead of happy-path).

```bash
make upload-c++ TAG=$TAG ACCOUNT_ID=$HTCGRID_ACCOUNT_ID REGION=$HTCGRID_REGION BUCKET_NAME=$S3_LAMBDA_HTCGRID_BUCKET_NAME
```

The above steps will upload new Worker Function zip in S3 bucket. However, only new worker pods will be able to benefit from this update. To apply the changes to the entire deployment it is necessary to remove all currently running worker pods (e.g., by executing ``kubectl delete $(kubectl get po -o name)``).

Each compute environment pod starts by executing lambda-init container (defined at ``source/compute_plane/shell/attach-layer``) which pulls the Worker function zip package from the S3_LAMBDA_HTCGRID_BUCKET_NAME S3 bucket at the pod boot time.


