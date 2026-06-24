# Copyright 2024 Amazon.com, Inc. or its affiliates.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

# Egress-only worker SG. No ingress: the worker is pull-based and reachable for ops
# only via SSM Session Manager. Redis (tcp/6379) is reachable because the control-plane
# Redis SG already allows the VPC CIDR.
resource "aws_security_group" "worker" {
  name        = "htc-ec2-worker-${local.suffix}"
  description = "HTC-Grid EC2 worker: egress only, SSM-managed"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all egress (AWS APIs via VPC endpoints / NAT)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "htc-ec2-worker-${local.suffix}"
    service = "htc-aws"
  }
}
