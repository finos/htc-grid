# Pricing Engine Example with QuantLib

This guide demonstrates deploying a financial pricing engine using [QuantLib](https://www.quantlib.org/docs.shtml), an open-source library for quantitative finance, to price European and American options.

## Overview

This example shows how to:
1. Create a custom worker using QuantLib
2. Deploy the worker to HTC-Grid
3. Submit portfolio pricing tasks
4. Retrieve and analyze results

## Understanding the Worker Code

### QuantLib Worker Structure

The pricing worker implements option pricing models:

```python
import QuantLib as ql
import json
from datetime import datetime

def lambda_handler(event, context):
    """
    Lambda handler for option pricing using QuantLib
    """
    try:
        # Parse input parameters
        option_type = event.get('option_type', 'european')
        spot_price = float(event.get('spot_price', 100))
        strike_price = float(event.get('strike_price', 100))
        risk_free_rate = float(event.get('risk_free_rate', 0.05))
        volatility = float(event.get('volatility', 0.2))
        time_to_maturity = float(event.get('time_to_maturity', 1.0))
        
        # Setup QuantLib environment
        calculation_date = ql.Date.todaysDate()
        ql.Settings.instance().evaluationDate = calculation_date
        
        # Define market data
        spot_handle = ql.QuoteHandle(ql.SimpleQuote(spot_price))
        flat_ts = ql.YieldTermStructureHandle(
            ql.FlatForward(calculation_date, risk_free_rate, ql.Actual365Fixed())
        )
        flat_vol_ts = ql.BlackVolTermStructureHandle(
            ql.BlackConstantVol(calculation_date, ql.NullCalendar(), volatility, ql.Actual365Fixed())
        )
        
        # Create the option
        maturity_date = calculation_date + int(time_to_maturity * 365)
        payoff = ql.PlainVanillaPayoff(ql.Option.Call, strike_price)
        
        if option_type.lower() == 'european':
            exercise = ql.EuropeanExercise(maturity_date)
            option = ql.VanillaOption(payoff, exercise)
            
            # Black-Scholes process
            bsm_process = ql.BlackScholesProcess(spot_handle, flat_ts, flat_vol_ts)
            
            # Analytical pricing engine
            engine = ql.AnalyticEuropeanEngine(bsm_process)
            
        elif option_type.lower() == 'american':
            exercise = ql.AmericanExercise(calculation_date, maturity_date)
            option = ql.VanillaOption(payoff, exercise)
            
            # Black-Scholes process
            bsm_process = ql.BlackScholesProcess(spot_handle, flat_ts, flat_vol_ts)
            
            # Binomial pricing engine
            engine = ql.BinomialVanillaEngine(bsm_process, "crr", 100)
        
        else:
            raise ValueError(f"Unsupported option type: {option_type}")
        
        # Price the option
        option.setPricingEngine(engine)
        price = option.NPV()
        
        # Calculate Greeks (for European options)
        greeks = {}
        if option_type.lower() == 'european':
            greeks = {
                'delta': option.delta(),
                'gamma': option.gamma(),
                'theta': option.theta(),
                'vega': option.vega(),
                'rho': option.rho()
            }
        
        return {
            'statusCode': 200,
            'body': {
                'option_price': price,
                'option_type': option_type,
                'input_parameters': {
                    'spot_price': spot_price,
                    'strike_price': strike_price,
                    'risk_free_rate': risk_free_rate,
                    'volatility': volatility,
                    'time_to_maturity': time_to_maturity
                },
                'greeks': greeks,
                'calculation_date': str(calculation_date)
            }
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': {
                'error': str(e),
                'input_event': event
            }
        }
```

### Dockerfile for QuantLib Worker

```dockerfile
FROM public.ecr.aws/lambda/python:3.13

# Install system dependencies
RUN yum update -y && \
    yum install -y gcc-c++ boost-devel && \
    yum clean all

# Install QuantLib
RUN pip install --no-cache-dir QuantLib

# Copy function code
COPY lambda_function.py ${LAMBDA_TASK_ROOT}

# Set the CMD to your handler
CMD ["lambda_function.lambda_handler"]
```

## Deploying the Pricing Engine

### 1. Build and Deploy Worker Image

```bash
# Navigate to your custom worker directory
cd examples/workloads/quantlib

# Build the Docker image
docker build -t quantlib-worker .

# Tag for ECR
docker tag quantlib-worker:latest $ECR_REGISTRY/quantlib-worker:latest

# Push to ECR
docker push $ECR_REGISTRY/quantlib-worker:latest
```

### 2. Update Grid Configuration

Add the QuantLib worker to your grid configuration:

```json
{
  "grid_config": {
    "lambda_runtimes": [
      {
        "runtime_name": "quantlib",
        "image_uri": "$ECR_REGISTRY/quantlib-worker:latest",
        "memory": 1024,
        "timeout": 300,
        "environment_variables": {
          "PYTHONPATH": "/var/task"
        }
      }
    ]
  }
}
```

### 3. Redeploy HTC-Grid

```bash
# Update the grid with new configuration
make apply-grid-config TAG=$TAG REGION=$HTCGRID_REGION
```

## Submitting Pricing Tasks

### Single Option Pricing

```python
import json
import boto3
from htc_grid_client import HTCGridClient

# Initialize client
client = HTCGridClient(config_file='agent_config.json')

# Define option parameters
option_task = {
    'runtime': 'quantlib',
    'payload': {
        'option_type': 'european',
        'spot_price': 100,
        'strike_price': 105,
        'risk_free_rate': 0.05,
        'volatility': 0.2,
        'time_to_maturity': 0.25
    }
}

# Submit task
session_id = client.submit_session([option_task])
print(f"Submitted session: {session_id}")

# Wait for completion and get results
results = client.get_session_results(session_id)
print(f"Option price: {results[0]['body']['option_price']}")
```

### Portfolio Pricing

```python
# Define a portfolio of options
portfolio_tasks = []

# Generate tasks for different strikes and maturities
strikes = [90, 95, 100, 105, 110]
maturities = [0.25, 0.5, 0.75, 1.0]

for strike in strikes:
    for maturity in maturities:
        task = {
            'runtime': 'quantlib',
            'payload': {
                'option_type': 'european',
                'spot_price': 100,
                'strike_price': strike,
                'risk_free_rate': 0.05,
                'volatility': 0.2,
                'time_to_maturity': maturity
            }
        }
        portfolio_tasks.append(task)

print(f"Submitting portfolio with {len(portfolio_tasks)} options")

# Submit portfolio
session_id = client.submit_session(portfolio_tasks)

# Monitor progress
while True:
    status = client.get_session_status(session_id)
    completed = status['completed_tasks']
    total = status['total_tasks']
    
    print(f"Progress: {completed}/{total} tasks completed")
    
    if completed == total:
        break
    
    time.sleep(5)

# Get all results
results = client.get_session_results(session_id)

# Analyze results
import pandas as pd

portfolio_data = []
for i, result in enumerate(results):
    if result['statusCode'] == 200:
        body = result['body']
        params = body['input_parameters']
        
        portfolio_data.append({
            'strike': params['strike_price'],
            'maturity': params['time_to_maturity'],
            'price': body['option_price'],
            'delta': body['greeks'].get('delta', 0),
            'gamma': body['greeks'].get('gamma', 0),
            'theta': body['greeks'].get('theta', 0),
            'vega': body['greeks'].get('vega', 0)
        })

df = pd.DataFrame(portfolio_data)
print("\nPortfolio Summary:")
print(df.groupby('maturity')['price'].describe())
```

## Advanced Pricing Scenarios

### Monte Carlo Simulation

Extend the worker for Monte Carlo pricing:

```python
def monte_carlo_pricing(event, context):
    """Monte Carlo option pricing"""
    import numpy as np
    
    # Parse parameters
    spot = float(event.get('spot_price', 100))
    strike = float(event.get('strike_price', 100))
    rate = float(event.get('risk_free_rate', 0.05))
    vol = float(event.get('volatility', 0.2))
    time_to_exp = float(event.get('time_to_maturity', 1.0))
    num_sims = int(event.get('num_simulations', 100000))
    
    # Generate random paths
    dt = time_to_exp
    z = np.random.standard_normal(num_sims)
    
    # Stock price at expiration
    st = spot * np.exp((rate - 0.5 * vol**2) * dt + vol * np.sqrt(dt) * z)
    
    # Option payoffs
    payoffs = np.maximum(st - strike, 0)  # Call option
    
    # Discounted expected payoff
    option_price = np.exp(-rate * time_to_exp) * np.mean(payoffs)
    
    return {
        'statusCode': 200,
        'body': {
            'option_price': float(option_price),
            'method': 'monte_carlo',
            'num_simulations': num_sims,
            'standard_error': float(np.std(payoffs) / np.sqrt(num_sims))
        }
    }
```

### Risk Scenario Analysis

Submit tasks for different market scenarios:

```python
# Define market scenarios
scenarios = [
    {'name': 'base_case', 'spot': 100, 'vol': 0.2, 'rate': 0.05},
    {'name': 'high_vol', 'spot': 100, 'vol': 0.4, 'rate': 0.05},
    {'name': 'low_rate', 'spot': 100, 'vol': 0.2, 'rate': 0.02},
    {'name': 'stress_down', 'spot': 80, 'vol': 0.3, 'rate': 0.03},
    {'name': 'stress_up', 'spot': 120, 'vol': 0.15, 'rate': 0.07}
]

scenario_tasks = []
for scenario in scenarios:
    task = {
        'runtime': 'quantlib',
        'payload': {
            'scenario_name': scenario['name'],
            'option_type': 'european',
            'spot_price': scenario['spot'],
            'strike_price': 100,
            'risk_free_rate': scenario['rate'],
            'volatility': scenario['vol'],
            'time_to_maturity': 1.0
        }
    }
    scenario_tasks.append(task)

# Submit and analyze scenario results
session_id = client.submit_session(scenario_tasks)
results = client.get_session_results(session_id)

# Compare scenario impacts
for i, result in enumerate(results):
    scenario_name = scenarios[i]['name']
    price = result['body']['option_price']
    print(f"{scenario_name}: ${price:.4f}")
```

## Performance Optimization

### Batch Processing

For large portfolios, implement batch processing:

```python
def batch_pricing_handler(event, context):
    """Process multiple options in a single task"""
    options = event.get('options', [])
    results = []
    
    for option_params in options:
        # Price each option
        result = price_single_option(option_params)
        results.append(result)
    
    return {
        'statusCode': 200,
        'body': {
            'batch_results': results,
            'batch_size': len(options)
        }
    }
```

### Caching and Optimization

Implement result caching for repeated calculations:

```python
import functools
import hashlib

@functools.lru_cache(maxsize=1000)
def cached_option_price(params_hash):
    """Cache option prices for identical parameters"""
    # Implementation here
    pass
```

## Monitoring Pricing Performance

### Key Metrics

Monitor pricing-specific metrics:
- Average pricing time per option
- Throughput (options priced per second)
- Error rates by option type
- Resource utilization per pricing task

### Custom CloudWatch Metrics

```python
import boto3

cloudwatch = boto3.client('cloudwatch')

def publish_pricing_metrics(pricing_time, option_type):
    """Publish custom metrics to CloudWatch"""
    cloudwatch.put_metric_data(
        Namespace='HTC-Grid/Pricing',
        MetricData=[
            {
                'MetricName': 'PricingLatency',
                'Dimensions': [
                    {
                        'Name': 'OptionType',
                        'Value': option_type
                    }
                ],
                'Value': pricing_time,
                'Unit': 'Milliseconds'
            }
        ]
    )
```

This pricing engine example demonstrates how HTC-Grid can handle complex financial computations at scale, processing thousands of option pricing calculations efficiently across distributed compute resources.
