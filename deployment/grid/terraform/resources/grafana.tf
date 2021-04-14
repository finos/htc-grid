# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/
 
resource "tls_private_key" "alb_certificate" {
  algorithm = "RSA"
  rsa_bits = 4096
}



resource "tls_self_signed_cert" "alb_certificate" {
  key_algorithm   = tls_private_key.alb_certificate.algorithm
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


resource "kubernetes_namespace" "grafana" {
  metadata {
    annotations = {
      name = "grafana"
    }
    name = "grafana"
  }
  depends_on = [
    module.eks,
    helm_release.alb_ingress_controller
  ]
  provisioner "local-exec" {
    when    = destroy
    command = "sleep 60"
  }
}

resource "helm_release" "grafana" {
  name       = "grafana"
  chart      = "grafana"
  namespace  = "grafana"
  repository = "https://grafana.github.io/helm-charts/"

  set {
    name  = "persistence.enabled"
    value = "false"
  }
  set {
    name  = "adminPassword"
    value = var.grafana_configuration.admin_password
  }

  set {
    type = "string"
    name = "ingress.annotations.alb\\.ingress\\.kubernetes\\.io/subnets"
    //value = "subnet-07df633bdcac0c135\\,subnet-07df633bdcac0c136\\,subnet-07df633bdcac0c137"
    value = join("\\,",var.vpc_private_subnet_ids)
  }

  set {
    type = "string"
    name = "alb\\.ingress\\.kubernetes\\.io/load-balancer-attributes" 
    value = "access_logs\\.s3\\.enabled=true\\,access_logs\\.s3\\.bucket=htc-grid-2020\\,access_logs\\.s3\\.prefix=my-app"
  }

   set {
     name  = "service.type"
     value = "NodePort"
   }
  set {
    name = "initChownData.image.repository"
    value = "${var.aws_htc_ecr}/busybox"
  }
  set {
    name = "initChownData.image.tag"
    value = var.grafana_configuration.initChownData_tag
  }
  set {
    name = "image.repository"
    value = "${var.aws_htc_ecr}/grafana"
  }
  set {
    name = "image.tag"
    value = var.grafana_configuration.grafana_tag
  }
  set {
    name = "downloadDashboardsImage.repository"
    value = "${var.aws_htc_ecr}/curl"
  }
  set {
    name = "downloadDashboardsImage.tag"
    value = var.grafana_configuration.downloadDashboardsImage_tag
  }
  set {
    name = "sidecar.image.repository"
    value = "${var.aws_htc_ecr}/k8s-sidecar"
  }
  set {
    name = "sidecar.image.tag"
    value = var.grafana_configuration.sidecar_tag
  }
  set {
    name = "sidecar.dashboards.enabled"
    value = "true"
  }
  set {
    name = "persistence.enabled"
    value = "false"
  }

  values = [
    file("resources/grafana_placement_conf.yaml"),
    file("resources/grafana_dashboard_k8s.yaml")
  ]

  depends_on = [
    kubernetes_namespace.grafana
  ]

}



resource "kubernetes_ingress" "grafana_ingress" {
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
        // "alb.ingress.kubernetes.io/auth-type"= "cognito"
        // "alb.ingress.kubernetes.io/auth-scope"= "openid"
        // "alb.ingress.kubernetes.io/auth-session-timeout"= "3600"
        // "alb.ingress.kubernetes.io/auth-session-cookie"= "AWSELBAuthSessionCookie"
        // "alb.ingress.kubernetes.io/auth-on-unauthenticated-request" = "authenticate"
        // "alb.ingress.kubernetes.io/auth-idp-cognito" = "{\"UserPoolArn\": \"arn:aws:cognito-idp:eu-west-1:123456789012:userpool/eu-west-1_tobereplaced\",\"UserPoolClientId\":\"ToBeReplaced\",\"UserPoolDomain\":\"${lower(local.suffix)}\"}"
    }
  }

 

  spec {
    rule {
      http {
        path {
          backend {
            service_name = "ssl-redirect"
            service_port = "use-annotation"
          }

          path = "/*"
        }
        path {
          // backend {
          //   service_name = "ssl_redirect"
          //   service_port = "use-annotation"
          // }

          backend {
            service_name = "grafana"
            service_port = 80
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
    kubernetes_namespace.grafana,
    helm_release.grafana,
    helm_release.alb_ingress_controller
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
    kubernetes_namespace.grafana,
    aws_iam_server_certificate.alb_certificate
  ]

}

