{
  "region": "{{region}}",
  "project_name": "{{image_tag}}",
  "grid_storage_service": "REDIS",
  "max_htc_agents": 30000,
  "min_htc_agents": 1,
  "dynamodb_default_read_capacity": 100,
  "dynamodb_default_write_capacity": 2000,
  "eks_worker_groups": [
      {
        "node_group_name": "worker-small-spot",
        "instance_types" : ["m6i.xlarge", "m6id.xlarge", "m6a.xlarge", "m6in.xlarge", "m5.xlarge","m5d.xlarge","m5a.xlarge", "m5ad.xlarge", "m5n.xlarge"],
        "capacity_type"  : "SPOT",
        "min_size"       : 1,
        "max_size"       : 5000,
        "desired_size"   : 1
      },
      {
        "node_group_name": "worker-medium-spot",
        "instance_types" : ["m6i.8xlarge", "m6id.8xlarge", "m6a.8xlarge", "m6in.8xlarge", "m5.8xlarge","m5d.8xlarge","m5a.8xlarge", "m5ad.8xlarge", "m5n.8xlarge"],
        "capacity_type"  : "SPOT",
        "min_size"       : 0,
        "max_size"       : 1000,
        "desired_size"   : 0
      },
      {
         "node_group_name": "worker-large-spot",
         "instance_types" : ["m6i.16xlarge", "m6id.16xlarge", "m6a.16xlarge", "m6in.16xlarge", "m5.16xlarge","m5d.16xlarge","m5a.16xlarge", "m5ad.16xlarge", "m5n.16xlarge"],
         "capacity_type"  : "SPOT",
         "min_size"       : 0,
         "max_size"       : 500,
         "desired_size"   : 0
      }
  ],
  "agent_configuration": {
    "lambda": {
      "minCPU"   : "900",
      "maxCPU"   : "1024",
      "minMemory": "2048",
      "maxMemory": "4096",
      "location" : "s3://{{workload_bucket_name}}/lambda.zip",
      "runtime"  : "provided"
    }
  },
  "enable_private_subnet" : {{enable_private_subnet}},
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
