{
  "region": "{{region}}",
  "project_name": "{{image_tag}}",
  "grid_storage_service": "REDIS",
  "max_htc_agents": 100,
  "min_htc_agents": 1,
  "dynamodb_default_read_capacity": 10,
  "dynamodb_default_write_capacity": 10,
  "eks_worker_groups": [
      {
        "node_group_name": "worker-small-spot",
        "instance_types" : ["m6i.xlarge", "m6id.xlarge", "m6a.xlarge", "m6in.xlarge", "m5.xlarge","m5d.xlarge","m5a.xlarge", "m5ad.xlarge", "m5n.xlarge"],
        "capacity_type"  : "SPOT",
        "min_size"       : 1,
        "max_size"       : 3,
        "desired_size"   : 1
      },
      {
        "node_group_name": "worker-medium-spot",
        "instance_types" : ["m6i.4xlarge", "m6id.4xlarge", "m6a.4xlarge", "m6in.4xlarge", "m5.4xlarge","m5d.4xlarge","m5a.4xlarge", "m5ad.4xlarge", "m5n.4xlarge"],
        "capacity_type"  : "SPOT",
        "min_size"       : 0,
        "max_size"       : 3,
        "desired_size"   : 0
      },
      {
         "node_group_name": "worker-large-spot",
         "instance_types" : ["m6i.8xlarge", "m6id.8xlarge", "m6a.8xlarge", "m6in.8xlarge", "m5.8xlarge","m5d.8xlarge","m5a.8xlarge", "m5ad.8xlarge", "m5n.8xlarge"],
         "capacity_type"  : "SPOT",
         "min_size"       : 0,
         "max_size"       : 3,
         "desired_size"   : 0
      }
  ],
  "agent_configuration": {
    "lambda": {
      "minCPU"   : "800",
      "maxCPU"   : "900",
      "minMemory": "1200",
      "maxMemory": "1900",
      "runtime"  : "python3.8",
      "s3_source": "s3://{{workload_bucket_name}}/lambda.zip",
      "s3_source_kms_key_arn"       : "{{workload_bucket_kms_key_arn}}",
      "lambda_handler_file_name"    : "{{python_file_handler}}",
      "lambda_handler_function_name": "{{python_function_handler}}"
    }
  },
  "enable_private_subnet" : true,
  "vpc_cidr_block_public" : 24,
  "vpc_cidr_block_private": 18,
  "input_role": [
      {
        "rolearn" : "arn:aws:iam::{{account_id}}:role/Admin",
        "username": "lambda",
        "groups"  : ["system:masters"]
      }
  ]
}
