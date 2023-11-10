locals {
  # Helm Releases
  helm_releases = {
    keda = {
      description      = "A Helm chart for KEDA"
      namespace        = "keda"
      create_namespace = true
      chart            = "keda"
      chart_version    = local.chart_version.keda
      repository       = "https://kedacore.github.io/charts"
      values = [templatefile("${path.module}/../../charts/values/keda.yaml", {
        aws_htc_ecr   = var.aws_htc_ecr
        keda_role_arn = module.keda_role.iam_role_arn
      })]
    }

    influxdb = {
      description      = "A Helm chart for InfluxDB"
      namespace        = "influxdb"
      create_namespace = true
      chart            = "influxdb"
      chart_version    = local.chart_version.influxdb
      repository       = "https://helm.influxdata.com/"
      values = [templatefile("${path.module}/../../charts/values/influxdb.yaml", {
        aws_htc_ecr = var.aws_htc_ecr
      })]
    }

    prometheus = {
      description      = "A Helm chart for Prometheus"
      namespace        = "prometheus"
      create_namespace = true
      chart            = "prometheus"
      chart_version    = local.chart_version.prometheus
      repository       = "https://prometheus-community.github.io/helm-charts"
      values = [templatefile("${path.module}/../../charts/values/prometheus.yaml", {
        aws_htc_ecr = var.aws_htc_ecr
        region      = var.region
      })]
    }

    grafana = {
      description      = "A Helm chart for Grafana"
      namespace        = "grafana"
      create_namespace = true
      chart            = "grafana"
      chart_version    = local.chart_version.grafana
      repository       = "https://grafana.github.io/helm-charts"
      values = [templatefile("${path.module}/../../charts/values/grafana.yaml", {
        aws_htc_ecr                       = var.aws_htc_ecr
        grafana_admin_password            = var.grafana_admin_password
        alb_certificate_arn               = aws_acm_certificate.alb_certificate.arn
        vpc_public_subnets                = join(",", var.vpc_public_subnet_ids)
        htc_metrics_dashboard_json        = indent(8, file("${path.module}/files/htc-dashboard.json"))
        kubernetes_metrics_dashboard_json = indent(8, file("${path.module}/files/kubernetes-dashboard.json"))
      })]
    }
  }
}


# As used in the EKS Blueprints Addons: https://github.com/aws-ia/terraform-aws-eks-blueprints-addons/blob/main/helm.tf
resource "helm_release" "this" {
  for_each = local.helm_releases

  name             = try(each.value.name, each.key)
  description      = try(each.value.description, null)
  namespace        = try(each.value.namespace, null)
  create_namespace = try(each.value.create_namespace, null)
  chart            = each.value.chart
  version          = try(each.value.chart_version, null)
  repository       = try(each.value.repository, null)
  values           = try(each.value.values, [])

  timeout                    = try(each.value.timeout, null)
  repository_key_file        = try(each.value.repository_key_file, null)
  repository_cert_file       = try(each.value.repository_cert_file, null)
  repository_ca_file         = try(each.value.repository_ca_file, null)
  repository_username        = try(each.value.repository_username, null)
  repository_password        = try(each.value.repository_password, null)
  devel                      = try(each.value.devel, null)
  verify                     = try(each.value.verify, null)
  keyring                    = try(each.value.keyring, null)
  disable_webhooks           = try(each.value.disable_webhooks, null)
  reuse_values               = try(each.value.reuse_values, null)
  reset_values               = try(each.value.reset_values, null)
  force_update               = try(each.value.force_update, null)
  recreate_pods              = try(each.value.recreate_pods, null)
  cleanup_on_fail            = try(each.value.cleanup_on_fail, null)
  max_history                = try(each.value.max_history, null)
  atomic                     = try(each.value.atomic, null)
  skip_crds                  = try(each.value.skip_crds, null)
  render_subchart_notes      = try(each.value.render_subchart_notes, null)
  disable_openapi_validation = try(each.value.disable_openapi_validation, null)
  wait                       = try(each.value.wait, false)
  wait_for_jobs              = try(each.value.wait_for_jobs, null)
  dependency_update          = try(each.value.dependency_update, null)
  replace                    = try(each.value.replace, null)
  lint                       = try(each.value.lint, null)

  dynamic "postrender" {
    for_each = try([each.value.postrender], [])

    content {
      binary_path = postrender.value.binary_path
      args        = try(postrender.value.args, null)
    }
  }

  dynamic "set" {
    for_each = try(each.value.set, [])

    content {
      name  = set.value.name
      value = set.value.value
      type  = try(set.value.type, null)
    }
  }

  dynamic "set_sensitive" {
    for_each = try(each.value.set_sensitive, [])

    content {
      name  = set_sensitive.value.name
      value = set_sensitive.value.value
      type  = try(set_sensitive.value.type, null)
    }
  }

  depends_on = [
    # Wait for EKS Blueprints Addons to be deployed first
    time_sleep.eks_blueprints_addons_dependency,
  ]
}
