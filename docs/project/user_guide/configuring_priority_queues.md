# Configuring Priority Queues

By default HTC-Grid comes configured with a single task queue implemented via SQS. However, HTC-Grid also supports task prioritization which is implemented using multiple SQS queues. In such configuration, each SQS queue corresponds to a specific priority. At runtime Agents attempt to pull tasks from the higher priority queues before checking queues containing lower priority.

To enable multiple priorities the following 3 steps need to be configured prior to HTC-Grid deployment


1. in ''deployment/grid/terraform/control_plane/sqs.tf'' modify variable **priorities** to have sufficient number of priorities that are required. Follow the same naming/numbering convention as outlined below
    ```python
    # Default configuration with 1 priority
    variable "priorities" {
        default     = {
            "__0" = 0
        }
    }
    ...
    # Example configuration with 3 priorities
    variable "priorities" {
        default     = {
            "__0" = 0
            "__1" = 1
            "__2" = 2
        }
    }

    ```

2. Configure GRID_CONFIG file (e.g., ''python_runtime_grid_config.json'') before deploying HTC-Grid. Note this file is auto-generated from the corresponding .tpl file located in ''examples/configurations/'' hence re-running ''make'' can overwrite modifications, consider updating .tpl file instead.

    ```python
    "task_queue_service": "PrioritySQS",
    "task_queue_config": "{'priorities':3}",
    ```
Set ''task_queue_service'' to **PrioritySQS** indicating that multiple priorities are used. Then, update ''task_queue_config'' to contain the appropriate number of priorities created in step 1.