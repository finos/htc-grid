---
title: "Deploying the pricing engine"
chapter: false
weight: 20
---

Now we understand what will be deployed, let's deploy the worker components and update HTC-Grid. 

### Build And Update HTC-Grid Pricing Engine Artifacts

The first step we will need to run is the set of makefiles that create the new worker container instance.

```
cd ~/environment/aws-htc-grid
make python-quant-lib-path TAG=$TAG REGION=$HTCGRID_REGION
```

The following command will build up the lambda and worker code that we just explored in the previous section, and upload the content to the S3 folder holding the lambda. It will also generate a configuration files that we will use moving forward for some extra configuration of the HTC-Grid. 

### Applying HTC-Grid Changes

The previous step has so generated a new file named `~/environment/aws-htc-gridgenerated/python_runtime_grid_config.json`. This file is pretty much exactly like the file we used during HTC-Grid installation except for a few sections of the file.

{{< highlight json "linenos=table,hl_lines=8-10,linenostart=30" >}}
  "agent_configuration": {
    "lambda": {
      "minCPU": "800",
      "maxCPU": "900",
      "minMemory": "1200",
      "maxMemory": "1900",
      "location" : "s3://main-lambda-unit-htc-grid-2b8838c8eecc/lambda.zip",
      "runtime": "python3.8",
      "lambda_handler_file_name" : "portfolio_pricing_engine",
      "lambda_handler_function_name" : "lambda_handler"
    }
  },
{{< / highlight >}}
 
The section highlighted provides a few information of the changes that we are applying. We are setting up the agent configuration to use the new lambda.zip with the `python3.8` runtime, and then selecting the file/library `portfolio_pricing_engine` and from there the lambda handler function named `lambda_handler`.

To apply this change, we just need to point and apply the new configuration using terraform.

```
make apply-custom-runtime  TAG=$TAG REGION=$HTCGRID_REGION
```

{{% notice note %}}
The execution of this command will prompt for `yes` to continue. Just type yes, for the command to proceed. You should see how this time around only a few changes are applied; Those changes have to do with the minimum changes required to modify the htc-agent configuration and redeploy it back again.
{{% /notice %}}




