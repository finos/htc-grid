# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


resource "tls_private_key" "alb_certificate" {
  algorithm = "RSA"
  rsa_bits  = 4096
}


resource "tls_self_signed_cert" "alb_certificate" {
  private_key_pem = tls_private_key.alb_certificate.private_key_pem

  # Certificate expires after 1 year.
  validity_period_hours = 8766

  # Generate a new certificate if Terraform is run within
  # 6 months of the certificate's expiration time.
  early_renewal_hours = 4380

  # Reasonable set of uses for a server SSL certificate.
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]

  subject {
    common_name         = "*.${var.region}.elb.${local.dns_suffix}"
    organization        = "Amazon.com, Inc."
    country             = "US"
    locality            = "WA"
    organizational_unit = "Amazon Web Services (AWS)"
  }
}


resource "aws_acm_certificate" "alb_certificate" {
  private_key      = tls_private_key.alb_certificate.private_key_pem
  certificate_body = tls_self_signed_cert.alb_certificate.cert_pem

  lifecycle {
    create_before_destroy = true
  }
}
