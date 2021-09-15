## Portfolio Evaluation using QuantLib

This example demonstrates the use of the [QuantLib](https://www.quantlib.org/) with its [SWIG Python bindings](https://github.com/lballabio/QuantLib-SWIG).

Components:
- /examples/workloads/python/quant_lib/portfolio_pricing_client.py client application that generates a portfolio of trades using simple portfolio generator. Trades then being split into individual tasks and sent to the HTC-Grid for computation. Once all tasks are completed, the client application merges results together to determine total value of the portfolio.

- /examples/workloads/python/quant_lib/portfolio_pricing_engine.py compute engine that receives a list of trades to evaluate (could be entire portfolio or just a single trade). The engine uses QuantLib to evaluate the value of the portfolio.



### Deployment

1. Follow all the steps in the main Readme file until you reach section **"Build HTC artifacts"**. In this section you will need to modify the `make` command replacing the `happy-path` with the `python-quant-lib-path` as follows:
    ```bash
    make python-quant-lib-path TAG=$TAG REGION=$HTCGRID_REGION
    ```
This will apply the following changes:
   - prepare python runtime environment for the lambda functions
   - generate 2 sample yaml files that will be used to deploy testing client containers.

2. After `make` is completed, please run
    ```bash
    make apply-python-runtime  TAG=$TAG REGION=$HTCGRID_REGION
    ```

Follow all the remaining steps as is in the main readme file.

### Running the example

Two default configurations are provided. The first configuration submits a portfolio containing a single trade.

```bash
kubectl apply -f ./generated/portfolio-pricing-single-trade.yaml
```

The second configuration submits a portfolio containing multiple trades.

```bash
kubectl apply -f ./generated/portfolio-pricing-book.yaml
```

Refer to the corresponding yaml files to change the configuration of the client application and refer to the help of the client application to identify all options.