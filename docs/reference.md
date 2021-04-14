# HTC-Grid API Reference

## Client API (Python)

This section outlines how client application can connect and interact with a deployed HTC-Grid.

AWSConnector is the main class responsible for communication with the HTC-Grid. Upon creating the 

```python
class api.connector.AWSConnector

from api.connector import AWSConnector
```
These are the available methods:

- [AWSConnector](#awsconnector)
- [authenticate](#authenticate)
- [send](#send)
- [get_results](#get_results)
- [cancel_sessions](#cancel_sessions)
### Constructor - **`AWSConnector`**


**Request Syntax**

```python


gridConnector = AWSConnector(client_config_data=
  {
      'grid_storage_service' : 'REDIS'|'S3',
      's3_bucket' : 'string',
      'redis_url' :'string',
      'public_api_gateway_url' : 'string',
      'private_api_gateway_url' : 'string',
      'api_gateway_key' : 'string',
      'user_pool_id' : 'string',
      'cognito_userpool_client_id' : 'string',
      'username' : 'string',
      'password' : 'string',
      'dynamodb_results_pull_interval_sec' : 'number',
      'task_input_passed_via_external_storage' : 'number',
      'region' : 'string'
  }
)
```

**Parameters** client_config_data (dict) [REQUIRED]

  * `grid_storage_service` - Determines which storage will be used for Data Plane 'REDIS'|'S3'
  * `s3_bucket` - The name of the S3 bucket that is used as a backend for Data Plane
  * `redis_url` - The URL of the Redis deployment that is used as a backend for the Data Plane
  * `public_api_gateway_url` -
  * `private_api_gateway_url` -
  * `api_gateway_key` -
  * `user_pool_id` -
  * `cognito_userpool_client_id` -
  * `username` - (optional) username for cognito userpool, if the field is not present, `username` property is read from environment variable `USERNAME`
  * `password` - (optional) password for cognito userpool, if the field is not present, `password` property is read from environment variable `PASSWORD`
  * `dynamodb_results_pull_interval_sec` - The frequency that the client uses to fetch results from DynamoDB.
  * `REGION` - Region where HTCGrid is deployed


**Return type**
AWSConnector Object

### Method - **`authenticate`**

There are currently three ways to authenticate a client.
1. Passing `username` and `password` via `client_config_data` when initialising AWSConnector (not recommended).
2. Setting `username` and `password` in the environmental variables
3. If client application and HTC-Grid are located in the same VPN then there is no need for explicit authentication. However, an additional environmental variable needs to be set `INTRA_VPC=1` allowing AWSConnector to skip username and password.

**Request Syntax**

```python
gridConnector.authenticate()
```

**Parameters**

None

**Return type**

None

**Returns**

None

### Method - **`send`**

This function is used to send task(s) to the HTC-Grid.

**Request Syntax**

```python
gridConnector.send(tasks_list=[
   {},
   ]
)
```

**Parameters** tasks_list (list) [REQUIRED]

A list of serialisable dictionaries. Each dictionary will be passed to the execution lambda function as an event argument. Each dictionary will be encoded to base 64 before being stored in the Data Plane and then decoded before being passed to the execution lambda function. Output produced by the lambda function will be passed the same way in the reverse direction. Encoding and decoding is done by the gridConnector, client only needs to provide serialisable dictionary as input and output of the lambda functions.

```python
input:
base64.b64encode(json.dumps(input_dict).encode('utf-8'))

output:
base64.b64decode(output_dict).decode('utf-8')
```


**Return type**

Dict

**Returns**

On successful submission, function returns a dictionary.

```python
{
   'session_id': 'string',
   'task_ids': [
      'string',
   ],
}
```

* `session_id` - a single session ID that is associated with the submission.
* `task_ids` - an ordered list of task IDs associated with each task that was submitted in the request.

### Method - **`get_results`**

Blocking function, waits until all tasks in the session are completed or until the timeout is expired. Function returns task IDs that have reached their terminal state (i.e., their states will not change).
- **Note**, function does not return outputs of the lambdas, it is responsibility of the client to retrieve results from the Data Plane asynchronously. This function merely indicates that tasks are completed and results can be retrieved from the Data Plane.

**Request Syntax**

```python
gridConnector.get_results(
   submission_response = {
      'session_id' : 'string',
      'task_ids': [
         'string',
      ],
   }
   timeout_sec = 'number'
)
```


**Parameters**

* `submission_response` - a dictionary that was returned after successful submission of tasks. `submission_response` must contain a valid `session_id` and a list of associated `task_ids`.
* `timeout_sec` - the function will periodically (based on `dynamodb_results_pull_interval_sec`) will try to pull for results until all tasks in the session are reached their terminal states or until the timeout is expires. The function uses the length of the `task_ids` list to determine the number of expected responses from the grid.

**Return type**

Dict

**Returns**

```python
{
   'finished': [
      'string',
   ]
   'finished_OUTPUT': [
      'string',
   ],
   'failed': [
      'string',
   ]
   'failed_OUTPUT': [
      'string',
   ],
   'cancelled': [
      'string',
   ]
   'cancelled_OUTPUT': [
      'string',
   ],
   'metadata': {
      'tasks_in_response': 'number'
   }
}
```
* `finished` (optional) - list of finished task IDs
* `finished_OUTPUT` (optional) - returns a string output produced by the lambda function
* `cancelled` (optional) list of cancelled task IDs
* `cancelled_OUTPUT` (optional) - returns a hardcoded string `read_from_REDIS` indicating that actual output should be read from Data Plane, it is responsibility of the client to do that.
* `failed` (optional) list of failed task IDs
* `failed_OUTPUT` (optional) - returns a hardcoded string `read_from_REDIS` indicating that actual output should be read from Data Plane, it is responsibility of the client to do that.
* `metadata`
   * `tasks_in_response` - total number of task in the terminal state (finished + failed + cancelled) returned to the response. For example, if none of the tasks in the session have reached their terminal states an expected return is as follows:
   ```python
   {
      'metadata': {
         'tasks_in_response': 0
      }
   }
   ```


### Method - **`cancel_sessions`**

**Request Syntax**

```python
response = gridConnector.cancel_sessions(
   [
      'string',
   ]
)
```

**Parameters**

* Function takes list of session IDs to be cancelled

**Return type**

Dict

**Returns**

Function returns dictionary of processed session IDs.

```python
{
   'string':
   {
      'cancelled_retrying': 0,
      'cancelled_pending': 3,
      'cancelled_processing': 1,
      'total_cancelled_tasks': 4
   },

   'string': {....}, #session - 2
   'string': {....}, #session - 3
}
```

* `string` - keys of the response dictionary are session IDs that were passed in for cancellation. Sub-dictionaries contain information about how many tasks were moved into cancelled state.
   * `cancellet_retying` - number of tasks moved from retrying state into cancelled state
   * `cancellet_pending` - number of tasks moved from pending state into cancelled state
   * `cancellet_processing` - number of tasks moved from processing state into cancelled state. **Note**, in current version, while state of tasks has been moved into cancelled processing will not be preemptively terminated (processing will continue until task is completed or failed). Failed tasks will not be retried.
   * `tatal_cancelled_tasks` - total number of tasks that has been affected by this invocation.