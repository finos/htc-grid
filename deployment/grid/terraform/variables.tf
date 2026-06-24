# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

#######################################
# Worker-plane backend selection (EKS vs EC2)
#######################################

variable "worker_backend" {
  description = "Which worker plane to deploy: 'eks' (Helm/KEDA, default) or 'ec2' (Docker Compose pairs scaled by ORB)."
  type        = string
  default     = "eks"

  validation {
    condition     = contains(["eks", "ec2"], var.worker_backend)
    error_message = "worker_backend must be either \"eks\" or \"ec2\"."
  }
}

# Worker instance TYPES are chosen by the selected ORB template (orb_template_id) — either an ABIS
# range or an enumerated machine_types list — not by a single type here. These two knobs are the
# only per-instance sizing inputs: they set the per-pair budget that each instance uses at boot to
# auto-pack NUM_PAIRS = floor(min(vCPU/ec2_worker_vcpus, mem_mb/ec2_worker_memory_mb)). The capacity
# controller scales the fleet in vCPUs using the same ec2_worker_vcpus, so the two stay consistent.
variable "ec2_worker_vcpus" {
  description = "vCPU budget per worker pair, used by the boot-time NUM_PAIRS auto-compute (ec2 backend)."
  type        = number
  default     = 1
}

variable "ec2_worker_memory_mb" {
  description = "Memory budget (MB) per worker pair, used by the boot-time NUM_PAIRS auto-compute (ec2 backend)."
  type        = number
  default     = 2048
}

variable "ec2_compose_plugin_version" {
  description = "docker-compose plugin version staged to S3 for worker instances (ec2 backend)."
  type        = string
  default     = "v2.29.7"
}

variable "orb_max_instances" {
  description = "ORB per-template max_instances cap, an upper bound on the fleet's instance count (ec2 backend)."
  type        = number
  default     = 5
}

# The capacity controller scales in vCPUs (EC2 Fleet TargetCapacityUnitType=vcpu): each pair needs
# ec2_worker_vcpus vCPUs, and AWS packs instances until the vCPU target is met. These knobs are in
# vCPUs / pairs, NOT instances (a heterogeneous fleet has no single "per instance" number).
variable "orb_target_pending_per_pair" {
  description = "Target pending tasks per worker pair; the controller sizes desired pairs = ceil(backlog / this). Tune by load test (ec2 backend)."
  type        = number
  default     = 4
}

variable "orb_min_vcpus" {
  description = "Minimum total fleet vCPUs the capacity controller keeps (ec2 backend; floor of the vCPU target)."
  type        = number
  default     = 0
}

variable "orb_max_vcpus" {
  description = "Maximum total fleet vCPUs the capacity controller may request (ec2 backend; ceiling of the vCPU target)."
  type        = number
  default     = 64
}

variable "orb_control_interval" {
  description = "Capacity-controller reconcile interval in seconds (ec2 backend)."
  type        = number
  default     = 60
}

# Which prebuilt ORB template to use (ec2 backend). The catalog lives in
# source/compute_plane/orb_orchestrator/config/aws_templates.json; every template is an EC2 Fleet
# (instant) with TargetCapacityUnitType=vcpu, differing only in instance selection (ABIS / enumerated
# / spot). Terraform grid-completes the selected one (subnet/SG/profile/AMI/user_data) and bakes it.
# Default is the enumerated EC2Fleet-Instant-OnDemand: orb-py's _validate_prerequisites
# (base_handler.py) rejects ABIS-only templates ("machine_types must be specified") because it never
# consults abis_instance_requirements, so EC2Fleet-Instant-ABIS cannot create until that upstream
# validator is fixed. The enumerated template carries machine_types and passes.
variable "orb_template_id" {
  description = "Prebuilt ORB template id to use for worker launches (ec2 backend); see config/aws_templates.json. EC2Fleet-Instant-ABIS is currently unusable (orb-py validator rejects ABIS-only templates)."
  type        = string
  default     = "EC2Fleet-Instant-OnDemand"
}

variable "ec2_drain_deadline_sec" {
  description = "Seconds a cordoned worker may finish in-flight work before being force-terminated on graceful scale-down (ec2 backend; ≈ worker compose stop_grace_period)."
  type        = number
  default     = 1500
}

variable "input_role" {
  description = "Additional IAM roles to add to the aws-auth configmap."
  type = list(object({
    rolearn  = string
    username = string
    groups   = list(string)
  }))
  default = []
}

variable "cluster_name" {
  description = "Name of EKS cluster in AWS"
  type        = string
  default     = "htc"
}

variable "lambda_runtime" {
  description = "Lambda runtine"
  type        = string
  default     = "python3.11"
}

variable "kubernetes_version" {
  description = "Name of EKS cluster in AWS"
  type        = string
  default     = "1.31"
}

variable "k8s_ca_version" {
  description = "Cluster autoscaler version"
  type        = string
  default     = "v1.31.0"
}

variable "k8s_keda_version" {
  description = "Keda version"
  type        = string
  default     = "2.11.2"
}

variable "aws_htc_ecr" {
  description = "URL of Amazon ECR image repostiories"
  type        = string
  default     = ""
}

variable "ddb_state_table" {
  description = "htc DinamoDB state table name"
  type        = string
  default     = "htc_tasks_state_table"
}

variable "dynamodb_autoscaling_enabled" {
  description = "Switches autoscaling for the dynamodb table"
  type        = bool
  default     = false
}

variable "dynamodb_billing_mode" {
  description = "Sets billing mode [PROVISIONED] or [PAY_PER_REQUEST]"
  type        = string
  default     = "PROVISIONED"
}

variable "task_queue_service" {
  description = "Configuration string for the type of queuing service to be used"
  type        = string
  default     = "SQS"
}

variable "task_queue_config" {
  description = "dictionary queue config"
  type        = string
  default     = "{'priorities':3}"
}

variable "sqs_queue" {
  description = "htc SQS queue name"
  type        = string
  default     = "htc_task_queue"
}

variable "sqs_dlq" {
  description = "htc SQS queue dlq name"
  type        = string
  default     = "htc_task_queue_dlq"
}

variable "s3_bucket" {
  description = "S3 bucket name"
  type        = string
  default     = "htc-data-bucket"
}

variable "grid_storage_service" {
  description = "Configuration string for internal results storage system"
  type        = string
  default     = "S3 htc-data-bucket-1"
}

variable "state_table_service" {
  description = "State Table service type"
  type        = string
  default     = "DynamoDB"
}

variable "state_table_config" {
  description = "Status Table configuration"
  type        = string
  default     = "{'retries':{'max_attempts':10, 'mode':'adaptive'}}"
}

variable "lambda_name_ttl_checker" {
  description = "Lambda name for ttl checker"
  type        = string
  default     = "ttl_checker"
}

variable "lambda_name_submit_tasks" {
  description = "Lambda name for submit task"
  type        = string
  default     = "submit_task"
}

variable "lambda_name_get_results" {
  description = "Lambda name for get result task"
  type        = string
  default     = "get_results"
}

variable "lambda_name_cancel_tasks" {
  description = "Lambda name for cancel tasks"
  type        = string
  default     = "cancel_tasks"
}

variable "metrics_are_enabled" {
  description = "If set to True(1) then metrics will be accumulated and delivered downstream for visualisation"
  type        = number
  default     = 1
}

variable "metrics_submit_tasks_lambda_connection_string" {
  description = "The type and the connection string for the downstream"
  type        = string
  default     = "influxdb 8086 measurementsdb submit_tasks"
}

variable "metrics_cancel_tasks_lambda_connection_string" {
  description = "The type and the connection string for the downstream"
  type        = string
  default     = "influxdb 8086 measurementsdb cancel_tasks"
}

variable "metrics_get_results_lambda_connection_string" {
  description = "The type and the connection string for the downstream"
  type        = string
  default     = "influxdb 8086 measurementsdb get_results"
}

variable "metrics_ttl_checker_lambda_connection_string" {
  description = "The type and the connection string for the downstream"
  type        = string
  default     = "influxdb 8086 measurementsdb ttl_checker"
}

variable "agent_use_congestion_control" {
  description = "Use Congestion Control protocol at pods to avoid overloading DDB"
  type        = string
  default     = "0"
}

variable "error_log_group" {
  description = "Log group for errors"
  type        = string
  default     = "grid_errors"
}

variable "error_logging_stream" {
  description = "Log stream for errors"
  type        = string
  default     = "lambda_errors"
}

variable "dynamodb_default_read_capacity" {
  description = "default read capacity  for all tables"
  type        = number
  default     = 100
}

variable "dynamodb_default_write_capacity" {
  description = "default write capacity for all tables"
  type        = number
  default     = 100
}

variable "namespace_metrics" {
  description = "NameSpace for metrics"
  type        = string
  default     = "CloudGrid/HTC/Scaling/"
}

variable "dimension_name_metrics" {
  description = "Dimensions name/value for the CloudWatch metrics"
  type        = string
  default     = "cluster_name"
}

variable "htc_path_logs" {
  description = "Path to fluentD to search de logs application"
  type        = string
  default     = "logs/"
}

variable "lambda_name_scaling_metrics" {
  description = "Lambda function name for metrics"
  type        = string
  default     = "scaling_metrics"
}

variable "lambda_name_node_drainer" {
  description = "Lambda function name for metrics"
  type        = string
  default     = "node_drainer"
}

variable "period_metrics" {
  description = "Period for metrics in minutes"
  type        = string
  default     = "1"
}

variable "metrics_name" {
  description = "Metrics name"
  type        = string
  default     = "pending_tasks_ddb"
}

# variable "average_period" {
#   description = "Average period in second used by the HPA to compute the current load on the system"
#   type        = number
#   default     = 30
# }

variable "metrics_event_rule_time" {
  description = "Fires event rule to put metrics"
  type        = string
  default     = "rate(1 minute)"
}

variable "htc_agent_name" {
  description = "name of the htc agent to scale out/in"
  type        = string
  default     = "htc-agent"
}

variable "htc_agent_namespace" {
  description = "kubernetes namespace for the deployment of the agent"
  type        = string
  default     = "default"
}

variable "eks_worker_groups" {
  type    = any
  default = []
}

variable "max_htc_agents" {
  description = "maximum number of agents that can run on EKS"
  type        = number
  default     = 100
}

variable "min_htc_agents" {
  description = "minimum number of agents that can run on EKS"
  type        = number
  default     = 1
}

variable "htc_agent_target_value" {
  description = "target value for the load on the system"
  type        = number
  default     = 2
}

variable "graceful_termination_delay" {
  description = "graceful termination delay in second for scaled in action"
  type        = number
  default     = 30
}

variable "empty_task_queue_backoff_timeout_sec" {
  description = "agent backoff timeout in second"
  type        = number
  default     = 0.5
}

variable "work_proc_status_pull_interval_sec" {
  description = "agent pulling interval"
  type        = number
  default     = 0.5
}

variable "task_ttl_expiration_offset_sec" {
  description = "agent TTL for task to time out in second"
  type        = number
  default     = 30
}

variable "task_ttl_refresh_interval_sec" {
  description = "reset interval for agent TTL"
  type        = number
  default     = 5.0
}

variable "dynamodb_results_pull_interval_sec" {
  description = "agent pulling interval for pending task in DDB"
  type        = number
  default     = 0.5
}

variable "agent_task_visibility_timeout_sec" {
  description = "default visibility timeout for SQS messages"
  type        = number
  default     = 3600
}

variable "task_input_passed_via_external_storage" {
  description = "Indicator for passing the args through stdin"
  type        = number
  default     = 1
}

variable "metrics_pre_agent_connection_string" {
  description = "pre agent connection string for monitoring"
  type        = string
  default     = "influxdb 8086 measurementsdb agent_pre"
}

variable "metrics_post_agent_connection_string" {
  description = "post agent connection string for monitoring"
  type        = string
  default     = "influxdb 8086 measurementsdb agent_post"
}

variable "agent_configuration_filename" {
  description = "filename where agent configuration (in json) is going to be stored"
  type        = string
  default     = "agent_config.json"
}

variable "api_gateway_version" {
  description = "version deployed by API Gateway"
  type        = string
  default     = "v1"
}

variable "enable_xray" {
  description = "Enable XRAY at the agent level"
  type        = number
  default     = 0
}

# variable "aws_xray_daemon_version" {
#   description = "version for the XRay daemon"
#   type        = string
#   default     = "latest"
# }

variable "enable_private_subnet" {
  description = "enable private subnet"
  type        = bool
  default     = false
}

variable "agent_configuration" {
  description = "Additional IAM roles to add to the aws-auth configmap."
  type        = any
  default     = {}
}

variable "grafana_admin_password" {
  description = "Holds the default/initial password that will be used for authenticating with Grafana"
  type        = string
  default     = ""
  sensitive   = true
}

variable "vpc_cidr_block_public" {
  description = "netmask for the cidr for each public subnet"
  type        = number
  default     = 24
}

variable "vpc_cidr_block_private" {
  description = "netmask for the cidr for each private subnet"
  type        = number
  default     = 24
}

variable "project_name" {
  description = "name of project"
  type        = string
  default     = ""
}

variable "kms_deletion_window" {
  description = "Number of days after which KMS key will be permanently deleted"
  type        = number
  default     = 7
}

variable "kms_key_admin_roles" {
  description = "List of roles to assign KMS Key Administrator permissions"
  type        = list(string)
  default     = []
}

variable "allowed_access_cidr_blocks" {
  description = "List of CIDR blocks which are allowed ingress/egress access from/to the VPC"
  type        = list(string)
  default     = []
}

variable "grafana_allowed_cidrs" {
  description = "CIDR blocks allowed to reach the internet-facing Grafana ALB (frontend SG inbound). Default is a deny placeholder; override per deploy."
  type        = list(string)
  default     = ["127.0.0.1/32"]
}

variable "eks_node_volume_size" {
  description = "Size in GB for EKS Worker Nodes"
  type        = number
  default     = 50
}
