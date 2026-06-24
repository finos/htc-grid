# Copyright 2024 Amazon.com, Inc. or its affiliates.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

# ORB orchestrator: the fleet-scaling orchestrator for the ec2 backend. Ports the proven
# CDK PoC (deployment/orb-poc/cdk/orb_poc_stack.py) to Terraform:
#   - 3 DynamoDB tables (machines/requests/templates) with the exact `id`:S schema ORB
#     DescribeTable-checks and skips its own CreateTable;
#   - a CMK encrypting them;
#   - a ZIP-packaged Lambda (orb-py + handler + config), outside any VPC, built in the SAM build
#     container (consistent with the other htc-grid Lambdas — no Docker image/ECR);
#   - a least-privilege role: DDB RW on the 3 tables, EC2 launch-template + run/terminate/
#     describe, SSM AMI read, KMS use, and iam:PassRole on the worker instance role.

locals {
  account_id = data.aws_caller_identity.current.account_id
  dns_suffix = data.aws_partition.current.dns_suffix
  partition  = data.aws_partition.current.partition

  tables = ["machines", "requests", "templates"]

  lambda_build_runtime = "${var.aws_htc_ecr}/ecr-public/sam/build-${var.lambda_runtime}:1"
  orb_source_dir       = "../../../source/compute_plane/orb_orchestrator"

  # Deploy-time ORB config: take the committed prebuilt template catalog, merge this grid's infra
  # fields into the SELECTED template (var.orb_template_id), and bake the result into the zip — the
  # handler no longer patches anything at cold start. The catalog is the single source of truth for
  # instance selection (ABIS / enumerated / spot); every template is an EC2 Fleet with
  # TargetCapacityUnitType=vcpu, so the controller and ORB always operate in vCPU units regardless
  # of which one is selected (it never inspects the template).
  staging_dir = "${path.module}/.orb-config-staging"

  catalog       = jsondecode(file("${local.orb_source_dir}/config/aws_templates.json"))
  catalog_ids   = [for t in local.catalog.templates : t.template_id]
  selected_tmpl = one([for t in local.catalog.templates : t if t.template_id == var.orb_template_id])

  # Grid infra fields merged onto the selected template (known to Terraform; ORB needs them concrete).
  grid_fields = {
    subnet_ids         = var.worker_subnet_ids
    security_group_ids = [var.worker_security_group_id]
    instance_profile   = var.worker_instance_profile_arn
    image_id           = var.worker_ami_id
    user_data          = var.worker_user_data_plain # plain text; ORB base64-encodes it itself
  }

  # Render ONLY the selected template, grid-completed (subnet/SG/profile/AMI/user_data + the per-grid
  # max_instances). ORB only ever launches the one the controller names, so shipping just it keeps
  # the bundled config minimal and avoids leaking the catalog's placeholder values. A bad
  # orb_template_id makes selected_tmpl null; the merge then errors, but terraform_data.template_guard
  # below surfaces a clear "not found, available: [...]" message at plan time.
  rendered_templates = {
    scheduler_type = local.catalog.scheduler_type
    templates = [
      merge(local.selected_tmpl, local.grid_fields, { max_instances = var.max_instances })
    ]
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# Deploy-time guards on the selected catalog template:
#   1. the selector must resolve to exactly one catalog template;
#   2. if that template uses ABIS, its vCPU/memory floor must fit at least one pair (else AWS could
#      launch a box too small for one pair, which would launch and idle).
# These fail the plan/apply with a clear message rather than mis-provisioning.
resource "terraform_data" "template_guard" {
  lifecycle {
    precondition {
      condition     = local.selected_tmpl != null
      error_message = "orb_template_id ${jsonencode(var.orb_template_id)} not found in the catalog. Available: ${jsonencode(local.catalog_ids)}."
    }
    precondition {
      # Keys here match the catalog JSON verbatim (jsondecode preserves them): the ABIS block is
      # "abisInstanceRequirements" with snake_case "vcpu_count"/"memory_mib" and "min"/"max".
      # ABIS-only floor check. Terraform does NOT reliably short-circuit ||, so a bare
      # .abisInstanceRequirements.vcpu_count.min access throws "object has no attribute ..." on an
      # enumerated (non-ABIS) template. Wrap the whole comparison in try(): when the ABIS block is
      # absent the deep access fails and try() yields true (the floor check does not apply).
      condition = try(
        local.selected_tmpl.abisInstanceRequirements.vcpu_count.min >= var.pair_cpu &&
        local.selected_tmpl.abisInstanceRequirements.memory_mib.min >= var.pair_memory,
        true
      )
      error_message = "Selected ABIS template's vcpu_count.min must be >= pair_cpu and memory_mib.min >= pair_memory (else AWS could launch a box too small for one pair)."
    }
  }
}

# --- CMK for the 3 state tables -------------------------------------------------
module "orb_state_kms_key" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 2.0"

  description             = "CMK for HTC-Grid ORB orchestrator DynamoDB state tables"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true
  key_administrators      = var.kms_key_admin_arns

  aliases = ["dynamodb/orb-orchestrator-${var.suffix}"]
}

# --- 3 DynamoDB state tables (PK id:S, on-demand, PITR, CMK) ---------------------
resource "aws_dynamodb_table" "orb_state" {
  for_each = toset(local.tables)

  name         = "${var.table_prefix}-${each.value}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = module.orb_state_kms_key.key_arn
  }

  tags = {
    service = "htc-aws"
  }
}

# --- Execution policy (attached by the lambda module to the role it creates) ----
# NOTE: the ec2 launch-template + RunInstances/Describe* statements use Resource "*" by necessity:
# CreateLaunchTemplate/RunInstances/ec2:Describe* are not resource-scopable pre-creation (and the
# Describe* actions reject any ARN). Tightening is possible only via a condition (e.g. restrict
# RunInstances/TerminateInstances to instances tagged for this grid) — deferred as future hardening;
# ORB only ever acts on the instances it launches. DynamoDB/KMS/SSM/PassRole below ARE scoped.
resource "aws_iam_policy" "orb_orchestrator" {
  name        = "orb-orchestrator-${var.suffix}"
  description = "ORB orchestrator: DynamoDB state, EC2 launch/terminate, SSM AMI, KMS, PassRole worker"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "OrbStateTables",
      "Action": [
        "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem",
        "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:Scan",
        "dynamodb:BatchGetItem", "dynamodb:BatchWriteItem", "dynamodb:DescribeTable"
      ],
      "Resource": ${jsonencode([for t in aws_dynamodb_table.orb_state : t.arn])},
      "Effect": "Allow"
    },
    {
      "Sid": "OrbLaunchTemplate",
      "Action": [
        "ec2:CreateLaunchTemplate", "ec2:CreateLaunchTemplateVersion",
        "ec2:DeleteLaunchTemplate", "ec2:DescribeLaunchTemplates",
        "ec2:DescribeLaunchTemplateVersions", "ec2:CreateTags"
      ],
      "Resource": "*",
      "Effect": "Allow"
    },
    {
      "Sid": "OrbFleet",
      "Action": [
        "ec2:CreateFleet", "ec2:DescribeFleets", "ec2:DescribeFleetInstances",
        "ec2:DeleteFleets", "ec2:ModifyFleet", "ec2:DescribeInstanceTypes"
      ],
      "Resource": "*",
      "Effect": "Allow"
    },
    {
      "Sid": "OrbInstances",
      "Action": [
        "ec2:RunInstances", "ec2:TerminateInstances", "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus", "ec2:DescribeImages", "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups"
      ],
      "Resource": "*",
      "Effect": "Allow"
    },
    {
      "Sid": "OrbAmiSsm",
      "Action": ["ssm:GetParameter", "ssm:GetParameters"],
      "Resource": "arn:${local.partition}:ssm:${var.region}::parameter/aws/service/ami-amazon-linux-latest/*",
      "Effect": "Allow"
    },
    {
      "Sid": "OrbStateKms",
      "Action": ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"],
      "Resource": "${module.orb_state_kms_key.key_arn}",
      "Effect": "Allow"
    },
    {
      "Sid": "OrbPassWorkerRole",
      "Action": ["iam:PassRole"],
      "Resource": "${var.worker_instance_role_arn}",
      "Effect": "Allow"
    }
  ]
}
EOF
}

# --- Deploy-time ORB config staging ---------------------------------------------
# Render a grid-complete aws_templates.json (subnet/SG/profile/AMI/user_data + the EC2 Fleet
# vCPU-unit native spec, with ABIS or enumerated instance selection) into a gitignored staging
# dir, alongside the unchanged grid-agnostic config.json. The lambda module's config source_path
# claim (below) points at this dir, so the zip ships a ready-to-use config and the handler no
# longer materializes anything at cold start. hash_extra on the module forces a repackage whenever
# the rendered content changes; depends_on guarantees the files exist before the build step runs.
resource "local_file" "aws_templates" {
  content  = jsonencode(local.rendered_templates)
  filename = "${local.staging_dir}/aws_templates.json"
}

resource "local_file" "orb_config_json" {
  content  = file("${local.orb_source_dir}/config/config.json") # verbatim; stays grid-agnostic
  filename = "${local.staging_dir}/config.json"
}

# --- The ZIP-packaged Lambda ----------------------------------------------------
# Built in the SAM build container (build_in_docker), like the other htc-grid Lambdas.
# The build: bundles orb_lambda.py + the staged config/, then pip-installs orb-py into the package.
# orb-py 1.7.0's DynamoDB backend works unmodified, so there is no patch step (it is installed as-is).
# ORB_CONFIG_DIR points at the bundled config; ORB_*_DIR writable dirs live in /tmp.
module "orb_orchestrator" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 5.0"

  function_name = "orb-orchestrator-${var.suffix}"
  handler       = "orb_lambda.handler"
  runtime       = var.lambda_runtime
  timeout       = 300
  memory_size   = 512

  build_in_docker = true
  docker_image    = local.lambda_build_runtime
  docker_additional_options = [
    "--platform", "linux/amd64",
  ]

  # Native pip build (runs INSIDE the SAM build container, so orb-py's native wheels match the
  # Lambda runtime). orb-py 1.7.0 is installed unmodified — its DynamoDB backend works out of the
  # box, so there is no build-time or cold-start patch step. The bundled config/ is the
  # DEPLOY-TIME-RENDERED staging dir (grid-complete aws_templates.json + grid-agnostic
  # config.json), bundled under orb-config/.
  source_path = [
    {
      path             = local.orb_source_dir
      pip_requirements = true # requirements.txt found in `path`
      patterns = [
        "orb_lambda.py",
        "!.*__pycache__.*",
        "!.*\\.pyc",
        "!\\.gitignore",
        "!docs/.*",
        "!config/.*",
        "!requirements\\.txt",
      ]
    },
    {
      path          = local.staging_dir
      prefix_in_zip = "orb-config"
    }
  ]

  role_name          = "role_orb_orchestrator_${var.suffix}"
  role_description   = "ORB orchestrator Lambda role"
  attach_policies    = true
  number_of_policies = 1
  policies           = [aws_iam_policy.orb_orchestrator.arn]

  attach_tracing_policy = true
  tracing_mode          = "Active"

  # Region + DynamoDB table prefix reach ORB via its OWN ORB_AWS_* env-var layer: orb-py's
  # AWSProviderConfig is a pydantic-settings BaseSettings (env_prefix="ORB_AWS_",
  # env_nested_delimiter="__"), so ORB_AWS_REGION and ORB_AWS_STORAGE__DYNAMODB__* are consumed
  # DIRECTLY — the bundled config.json deliberately omits region/table_prefix so these env vars win.
  # The launch-template values (subnet/SG/profile/AMI/user_data + instance selection) are now BAKED
  # into the rendered aws_templates.json at deploy time (see local_file.aws_templates), so they are
  # NOT passed as env vars anymore and the handler does not materialize anything at cold start.
  # ORB_CONFIG_DIR is the bundled (read-only) config; writable ORB dirs go under /tmp.
  # ORB_ALLOW_TERMINATE_ALL is left UNSET so the fleet-wide kill switch is disabled.
  environment_variables = {
    # Powertools structured logging: service name groups records; level is env-driven.
    POWERTOOLS_SERVICE_NAME = "orb_orchestrator"
    LOG_LEVEL               = "INFO"
    ORB_CONFIG_DIR          = "/var/task/orb-config"
    ORB_PROVIDER            = "aws"
    ORB_ROOT_DIR            = "/tmp/orb"
    ORB_WORK_DIR            = "/tmp/orb/work"
    ORB_LOG_DIR             = "/tmp/orb/logs"
    ORB_CACHE_DIR           = "/tmp/orb/cache"
    ORB_SCRIPTS_DIR         = "/tmp/orb/scripts"
    ORB_HEALTH_DIR          = "/tmp/orb/health"

    # Consumed by orb-py's AWSProviderConfig BaseSettings directly (no handler substitution).
    ORB_AWS_REGION                          = var.region
    ORB_AWS_STORAGE__DYNAMODB__TABLE_PREFIX = var.table_prefix
    ORB_AWS_STORAGE__DYNAMODB__REGION       = var.region
  }

  tags = {
    service = "htc-aws"
  }

  # Fold the rendered templates into the package hash so any change to instance selection / grid
  # values forces a repackage; depends_on so the staged files exist before the build step runs.
  hash_extra = sha256(jsonencode(local.rendered_templates))

  depends_on = [
    aws_dynamodb_table.orb_state,
    local_file.aws_templates,
    local_file.orb_config_json,
  ]
}
