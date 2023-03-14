# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/
 
resource "tls_private_key" "alb_certificate" {
  algorithm = "RSA"
  rsa_bits = 4096
}



resource "tls_self_signed_cert" "alb_certificate" {
  private_key_pem = tls_private_key.alb_certificate.private_key_pem

  # Certificate expires after 12 hours.
  validity_period_hours = 240

  # Generate a new certificate if Terraform is run within three
  # hours of the certificate's expiration time.
  early_renewal_hours = 3

  # Reasonable set of uses for a server SSL certificate.
  allowed_uses = [
      "key_encipherment",
      "digital_signature",
      "server_auth",
  ]


  subject {
      common_name  = "amazon.com"
      organization = "AWS"
      country = "LU"
      locality = "LU"
      organizational_unit = "AWS"
  }
}

# For example, this can be used to populate an AWS IAM server certificate.
resource "aws_iam_server_certificate" "alb_certificate" {
  name             = "alb_certificate_self_signed_cert-${local.suffix}"
  certificate_body = tls_self_signed_cert.alb_certificate.cert_pem
  private_key      = tls_private_key.alb_certificate.private_key_pem
}






resource "kubernetes_ingress_v1" "grafana_ingress" {
  wait_for_load_balancer = true
  metadata {
    name = "grafana-ingress"
    namespace = "grafana"
    annotations = {
        "kubernetes.io/ingress.class"=  "alb"
        "alb.ingress.kubernetes.io/scheme" = "internet-facing"

        "alb.ingress.kubernetes.io/listen-ports" = "[{\"HTTP\": 80},{\"HTTPS\":443}]"
        "alb.ingress.kubernetes.io/certificate-arn"= aws_iam_server_certificate.alb_certificate.arn
        "alb.ingress.kubernetes.io/actions.ssl-redirect"= "{\"Type\": \"redirect\", \"RedirectConfig\": { \"Protocol\": \"HTTPS\", \"Port\": \"443\", \"StatusCode\": \"HTTP_301\"}}"
        "alb.ingress.kubernetes.io/subnets" = join(",",var.vpc_public_subnet_ids)
    }
  }



  spec {
    rule {
      http {
        path {
          backend {
            service {
              name = "ssl-redirect"
              port  {
                name = "use-annotation"
              }
            }
          }

          path = "/*"
        }
        path {
          // backend {
          //   service_name = "ssl_redirect"
          //   service_port = "use-annotation"
          // }

          backend {
            service {
              name = "grafana"
              port {
                number = 80
              }
            }
          }

          path = "/*"
        }

      }
    }
  }

  // provisioner "local-exec" {
  //   command = "kubectl -n grafana patch ingress grafana-ingress --type='json' -p=[] " //${file(resource/patch-ingress.json)}"
  //   environment = {
  //     KUBECONFIG = module.eks.kubeconfig_filename
  //   }
  // }
  depends_on = [
    #kubernetes_namespace.grafana,
    module.eks_blueprints_kubernetes_addons,
  ]
  provisioner "local-exec" {
    when    = destroy
    command = "sleep 60"
  }
}

resource "kubernetes_config_map" "dashboard" {
  metadata {
    namespace = "grafana"
    name = "grafana-dashboard"
    labels =  {
       grafana_dashboard= "1"
    }
  }

  data = {
    "htc-metrics.json" = file("${path.module}/htc-dashboard.json")
    "kubernetes-metrics.json" = file("${path.module}/kubernetes-dashboard.json")
  }
  
  depends_on = [
    #kubernetes_namespace.grafana,
    aws_iam_server_certificate.alb_certificate,
    module.eks_blueprints_kubernetes_addons
  ]

}

