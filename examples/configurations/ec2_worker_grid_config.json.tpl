{
  "region": "{{region}}",
  "project_name": "{{image_tag}}",
  "worker_backend": "ec2",
  "grid_storage_service": "REDIS",
  "max_htc_agents": 100,
  "min_htc_agents": 1,
  "dynamodb_default_read_capacity": 10,
  "dynamodb_default_write_capacity": 10,
  "agent_configuration": {
    "lambda": {
      "minCPU"   : "800",
      "maxCPU"   : "900",
      "minMemory": "1200",
      "maxMemory": "1900",
      "runtime"  : "provided",
      "s3_source": "s3://{{workload_bucket_name}}/lambda.zip",
      "s3_source_kms_key_arn" : "{{workload_bucket_kms_key_arn}}"
    }
  },
  "ec2_worker_vcpus": {{ec2_worker_vcpus}},
  "ec2_worker_memory_mb": {{ec2_worker_memory_mb}},
  "orb_max_instances": {{orb_max_instances}},
  "orb_target_pending_per_pair": {{orb_target_pending_per_pair}},
  "orb_min_vcpus": {{orb_min_vcpus}},
  "orb_max_vcpus": {{orb_max_vcpus}},
  "orb_control_interval": {{orb_control_interval}},
  "orb_template_id": "{{orb_template_id}}",
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
