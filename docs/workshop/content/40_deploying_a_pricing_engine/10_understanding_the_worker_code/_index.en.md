---
title: "Understanding the worker code"
chapter: false
weight: 10
---

The worker code for the pricing engine is available in the project example folder at: https://github.com/awslabs/aws-htc-grid/tree/main/examples/workloads/python/quant_lib


The entry-point for the engine is available in the [portfolio_pricing_engine.py lines 28 to 34](https://github.com/awslabs/aws-htc-grid/blob/main/examples/workloads/python/quant_lib/portfolio_pricing_engine.py#L28-L34): 

{{< highlight python "linenos=table,hl_lines=8-10,linenostart=28" >}}
def lambda_handler(event, context):

    results = [evaluate_option(opt) for opt in event["portfolio"]]
    logging.info(results)
    return {
        "results": results
    }
{{< / highlight >}}

For those familiar with AWS Lambda service, you can see the interface is exactly the same. In this case the pricing engine is expecting a file similar to the one provided in the example **[sample_portfolio.json](https://github.com/awslabs/aws-htc-grid/blob/main/examples/client/python/sample_portfolio.json)**. The json file defines a vector of (a simplification of) Option trades and the engine they should be priced with.

{{< highlight python "linenos=table,linenostart=1" >}}
{
    "portfolio": [
        {
            "tradeType": "option",
            "exercise": "European",
            "engineName": "AnalyticEuropeanEngine",
            "engineParameters": {},
            "tradeParameters": {
                "evaluationDate": "15 5 1998",
                "exerciseDate": "17 5 1999",
                "payoff": 8.0,
                "underlying": 7.0,
                "dividendYield": 0.05,
                "volatility": 0.10,
                "riskFreeRate": 0.05
            }
        },
{{< / highlight >}}

As you can see in the worker code, the worker will take this vector of trade definitions and start running one by one the valuations, storing the results in the result vector. The result vector will be ultimately serialised and sent over the data plane for the client to retrieve the results.

The directory where the engine is deployed has a few extra files: 

* **Makefile** : Part of the `make` machinery to help with the build of different HTC-Grid Artifacts. In this case to build up the components of this example. 
* **Dockerfile.Build**: To make sure we are consistent, we use Dockerfile.Build files that allow us to build and compile most of our applications within containers. That way we don't have dependencies on the development environment where we execute the build process.







