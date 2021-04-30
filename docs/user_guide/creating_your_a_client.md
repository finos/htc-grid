# Configuring Client and Sending Tasks to the HTC Grid

We assume that all previous steps have been successfully completed, there is at least one pod that is running in the system and thus can execute tasks. Furthermore, we consider that client application will be running on an EC2 instance.

1. Setup a Cloud9 (EC2) Instance
    a) Go to the AWS console in the Cloud9 service
    b) Click on "Create your environment"
    c) Select your favorite OS and machine type (at least t3.small)
    d) In network settings, please used the VPC id and, the subnet that was created as part of your infrastructure deployment (look for your unique suffix in the VPC/subnet pages of the AWS console).

     * Go to the AWS console  in the VPC service.
     * Find the VPC id where the EKS cluster
     * Find a public subnet id attached to the VPC where the EKS cluster is running. (The public subnet should have an Internet Gateways and should be able to assign IPs)

    e) Click on create and wait for the validation

2. Checkout the same version of the repository as was used to deploy infrastructure

3. Upload the infrastructure settings to the Cloud9 instance so that client knows ALB endpoints and connects to the right instance of the HTC grid.
    a) On the machine that was used for deployment. Go in ./infrastructure/ folder where `terraform apply` has been run.

    ```
    terraform output agent_config
    ```

    c) copy the produced `Agent_config.json` file into cloud9 and note the location
    d) set environment variable `export AGENT_CONFIG_FILE=/<path>/Agent_config.json`
    e) set environment variable `export INTRA_VPC=1` This will allow client to send tasks to ALB without authentication through Cognito as it is deployed in the same VPC as the grid. For clients running from outside the VPC an additional authentication step is required.


4. From the root folder execute:

    ```bash
    make packages

    #make sure that these two files are created:
    ls ./dist/
    api-0.1-py3-none-any.whl  utils-0.1-py3-none-any.whl
    ```

    If these files are not created or if it is based on python 2, then run virtualenv as described at the start of the document

5. Install clients requirements on Cloud9

    ```bash
    cd ./examples/client/python/
    pip3 install -r requirements.txt
    ```

6. Sample client and workload generator is located here [`./examples/client/python/client.py`](./examples/client/python/client.py). Read help and browse through the code to be able to submit tasks and sessions, see examples below:

    To show the example client application help

    ```bash
    python3 ./client.py --help
    ```

    To submits a single session (containing a single task by default)

    ```bash
    python3 ./client.py  --njobs 1
    ```

    To submits 2 batches of 4 sessions each, where each session contains 3 tasks. Total 4*3*2 24 tasks.

    ```bash
    python3 ./client.py  --njobs 2 --job_size 3 --job_batch_size 4
    ```
    To tarts 5 threads, each submits a single session wth 1 job with a custom arguments to the executable.

    ```bash
    python3 ./client.py  --njobs 1 --worker_arguments "5000 1 100" -nthreads 5
    ```


