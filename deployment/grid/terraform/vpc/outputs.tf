# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


output "vpc_id" {
  description = "Id of the VPC created"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC created"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "ids of the private subnet created"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "ids of the private subnet created"
  value       = module.vpc.public_subnets
}

output "default_security_group_id" {
  description = "id of the default security group created with the VPC"
  value       = module.vpc.default_security_group_id
}
