# Copyright 2024 Amazon.com, Inc. or its affiliates.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

# Capacity controller: EventBridge-scheduled Lambda that reconciles worker capacity to
# the backlog by invoking the ORB orchestrator (create/terminate). Mirrors the EKS
# KEDA+Cluster-Autoscaler control loop for the ec2 backend.
#
# Single-flight is enforced by reserved_concurrent_executions = 1 (ADR-001): at most one
# tick runs at a time, so overlapping/duplicate invocations cannot double-issue ORB's
# non-idempotent create. (No DynamoDB lock — concurrency=1 frees on exit, with no stuck
# state. Sequential over-creation is still prevented by ORB status listing new instances
# as pending on the next tick.)

locals {
  account_id           = data.aws_caller_identity.current.account_id
  dns_suffix           = data.aws_partition.current.dns_suffix
  partition            = data.aws_partition.current.partition
  lambda_build_runtime = "${var.aws_htc_ecr}/ecr-public/sam/build-${var.lambda_runtime}:1"
  function_name        = "capacity_controller-${var.suffix}"

  # EventBridge rate() only supports minutes/hours/days (min 1 minute) with singular/plural
  # agreement. Convert control_interval (seconds) to a valid minute-based expression.
  control_minutes     = max(1, ceil(var.control_interval / 60))
  schedule_expression = local.control_minutes == 1 ? "rate(1 minute)" : "rate(${local.control_minutes} minutes)"
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# Controller permissions: invoke orchestrator, read backlog from SQS, query state table, drain.
resource "aws_iam_policy" "controller" {
  name        = "capacity-controller-${var.suffix}"
  description = "Capacity controller: invoke ORB orchestrator, read SQS backlog, query state table, drain instances"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "InvokeOrchestrator",
      "Action": ["lambda:InvokeFunction"],
      "Resource": "${var.orchestrator_function_arn}",
      "Effect": "Allow"
    },
    {
      "Sid": "ReadBacklogQueue",
      "Action": ["sqs:GetQueueUrl", "sqs:GetQueueAttributes"],
      "Resource": "arn:${local.partition}:sqs:${var.region}:${local.account_id}:${var.sqs_queue}*",
      "Effect": "Allow"
    },
    {
      "Sid": "DecryptQueue",
      "Action": ["kms:Decrypt", "kms:DescribeKey"],
      "Resource": "${var.sqs_kms_key_arn}",
      "Effect": "Allow"
    },
    {
      "Sid": "QueryLiveTasks",
      "Action": ["dynamodb:Query"],
      "Resource": [
        "${var.state_table_arn}",
        "${var.state_table_arn}/index/*"
      ],
      "Effect": "Allow"
    },
    {
      "Sid": "DecryptStateTable",
      "Action": ["kms:Decrypt", "kms:DescribeKey"],
      "Resource": "${var.state_table_kms_key_arn}",
      "Effect": "Allow"
    },
    {
      "Sid": "DrainStateTags",
      "Action": ["ec2:CreateTags", "ec2:DeleteTags", "ec2:DescribeInstances"],
      "Resource": "*",
      "Effect": "Allow"
    },
    {
      "Sid": "DrainSsmCommand",
      "Action": ["ssm:SendCommand"],
      "Resource": [
        "arn:${local.partition}:ssm:${var.region}::document/AWS-RunShellScript",
        "arn:${local.partition}:ec2:${var.region}:${local.account_id}:instance/*"
      ],
      "Effect": "Allow"
    }
  ]
}
EOF
}

module "capacity_controller" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 5.0"

  # Bundle the shared state-table DAL (api-v0.1) + utils so the controller can read the
  # live-task heartbeat to detect which workers are busy (same libs the ttl_checker uses).
  source_path = [
    {
      path             = "../../../source/compute_plane/python/lambda/capacity_controller"
      pip_requirements = "../../../source/compute_plane/python/lambda/capacity_controller/requirements.txt"
      patterns = [
        "!tests/.*",
        "!test_.*\\.py",
        "!.*__pycache__.*",
        "!.*\\.pyc",
      ]
    },
    {
      path = "../../../source/client/python/api-v0.1/"
      patterns = [
        "!README\\.md",
        "!setup\\.py",
        "!LICENSE*",
      ]
    },
    {
      path = "../../../source/client/python/utils/"
      patterns = [
        "!README\\.md",
        "!setup\\.py",
        "!LICENSE*",
      ]
    },
  ]
  function_name   = local.function_name
  build_in_docker = true
  docker_image    = local.lambda_build_runtime
  docker_additional_options = [
    "--platform", "linux/amd64",
  ]
  handler     = "ec2_capacity_controller.handler"
  memory_size = 256
  timeout     = 120
  runtime     = var.lambda_runtime

  # Single-flight: at most one reconcile tick runs at a time (ADR-001).
  reserved_concurrent_executions = 1

  role_name        = "role_capacity_controller_${var.suffix}"
  role_description = "Capacity controller Lambda role"

  attach_policies    = true
  number_of_policies = 1
  policies           = [aws_iam_policy.controller.arn]

  # NOT VPC-attached: the controller only calls regional AWS APIs — Lambda, SQS, DynamoDB,
  # EC2/SSM (no in-VPC resources). The htc VPC has no NAT and no 'lambda' interface endpoint, so a
  # VPC-attached controller would hang invoking the orchestrator. Running outside the VPC (like the
  # orchestrator) gives it direct AWS API access.

  attach_tracing_policy = true
  tracing_mode          = "Active"

  environment_variables = {
    # Powertools structured logging: service name groups this Lambda's records; level is
    # env-driven (no code change to switch to DEBUG).
    POWERTOOLS_SERVICE_NAME    = "capacity_controller"
    LOG_LEVEL                  = "INFO"
    REGION                     = var.region
    DRAIN_DEADLINE_SEC         = tostring(var.drain_deadline_sec)
    ORCHESTRATOR_FUNCTION_NAME = var.orchestrator_function_name
    ORB_TEMPLATE_ID            = var.orb_template_id
    TASK_QUEUE_SERVICE         = var.task_queue_service
    TASK_QUEUE_CONFIG          = var.task_queue_config
    TASKS_QUEUE_NAME           = var.tasks_queue_name
    # Read at import by the shared queue DAL's grid_error_logger (no agent config file in-Lambda).
    ERROR_LOG_GROUP         = var.error_log_group
    ERROR_LOGGING_STREAM    = var.error_logging_stream
    PAIR_CPU                = tostring(var.pair_cpu)
    PAIR_MEMORY             = tostring(var.pair_memory)
    MIN_VCPUS               = tostring(var.min_vcpus)
    MAX_VCPUS               = tostring(var.max_vcpus)
    TARGET_PENDING_PER_PAIR = tostring(var.target_pending_per_pair)
    STATE_TABLE_NAME        = var.state_table_name
    STATE_TABLE_SERVICE     = var.state_table_service
    STATE_TABLE_CONFIG      = var.state_table_config
  }

  tags = {
    service = "htc-aws"
  }
}

# --- EventBridge schedule --------------------------------------------------------
resource "aws_cloudwatch_event_rule" "tick" {
  name                = "capacity-controller-tick-${var.suffix}"
  description         = "Capacity controller reconcile tick"
  schedule_expression = local.schedule_expression
}

resource "aws_cloudwatch_event_target" "tick" {
  rule      = aws_cloudwatch_event_rule.tick.name
  target_id = "lambda"
  arn       = module.capacity_controller.lambda_function_arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowControllerExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = module.capacity_controller.lambda_function_name
  principal     = "events.${local.dns_suffix}"
  source_arn    = aws_cloudwatch_event_rule.tick.arn
}
