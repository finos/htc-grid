{
  "region": "{{region}}",
  "project_name": "{{image_tag}}",
  "grid_storage_service" : "REDIS",
  "max_htc_agents": 3000,
  "min_htc_agents": 1,
  "dynamodb_default_read_capacity" : 4000,
  "dynamodb_default_write_capacity" : 4000,
  "eks_worker_groups" : [
      {
        "name"                    : "worker-small-spot",
        "override_instance_types" : ["m5.2xlarge","m5d.2xlarge", "m5a.2xlarge", "c5.2xlarge", "r5.2xlarge"],
        "spot_instance_pools"     : 0,
        "asg_min_size"            : 0,
        "asg_max_size"            : 300,
        "asg_desired_capacity"    : 1,
        "on_demand_base_capacity" : 0
      },
      {
        "name"                    : "worker-medium-spot",
        "override_instance_types" : ["m5.4xlarge","m5d.4xlarge", "m5a.4xlarge", "c5.4xlarge", "r5.4xlarge"],
        "spot_instance_pools"     : 0,
        "asg_min_size"            : 0,
        "asg_max_size"            : 300,
        "asg_desired_capacity"    : 0,
        "on_demand_base_capacity" : 0

      },
      {
        "name"                    : "worker-large-spot",
        "override_instance_types" : ["m5.8xlarge","m5d.8xlarge", "m5a.8xlarge", "c5.9xlarge", "r5.8xlarge"],
        "spot_instance_pools"     : 0,
        "asg_min_size"            : 0,
        "asg_max_size"            : 300,
        "asg_desired_capacity"    : 0,
        "on_demand_base_capacity" : 0

      },
      {
        "name"                    : "worker-xlarge-spot",
        "override_instance_types" : ["m5.12xlarge","m5d.12xlarge", "m5a.12xlarge", "c5.12xlarge", "r5.12xlarge"],
        "spot_instance_pools"     : 0,
        "asg_min_size"            : 0,
        "asg_max_size"            : 300,
        "asg_desired_capacity"    : 0,
        "on_demand_base_capacity" : 0

      }
  ],
  "agent_configuration": {
    "lambda": {
      "minCPU": "800",
      "maxCPU": "900",
      "minMemory": "1200",
      "maxMemory": "1900",
      "location" : "s3://{{workload_bucket_name}}/lambda.zip",
      "runtime": "python3.8",
      "lambda_handler_file_name" : "{{python_file_handler}}",
      "lambda_handler_function_name" : "{{python_function_handler}}"
    }
  },
  "enable_private_subnet" : {{enable_private_subnet}},
  "vpc_cidr_block_public" :24,
  "vpc_cidr_block_private" :18,
  "input_role":[
      {
        "rolearn"  : "arn:aws:iam::{{account_id}}:role/Admin",
        "username" : "lambda",
        "groups"   : ["system:masters"]
      }
  ]
}