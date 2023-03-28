{
  "region": "{{region}}",
  "project_name": "{{image_tag}}",
  "grid_storage_service" : "REDIS",
  "max_htc_agents": 100,
  "min_htc_agents": 1,
  "dynamodb_default_read_capacity" : 10,
  "dynamodb_default_write_capacity" : 10,
  "eks_worker_groups" : [
       {
        "node_group_name"         : "worker-small-spot",
        "instance_types" : ["m5.xlarge","m5d.xlarge","m5a.xlarge"],
        "capacity_type"       : "spot",
        "min_size"            : 0,
        "max_size"            : 3,
        "desired_size"    : 1

      },
      {
        "node_group_name"         : "worker-medium-spot",
        "instance_types" : ["m5.2xlarge","m5d.2xlarge", "m5a.2xlarge"],
        "capacity_type"       : "spot",
        "min_size"            : 0,
        "max_size"            : 3,
        "desired_size"    : 0
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