# -----------------------------------------------------------------------------
# cert-manager és a Let's Encrypt ClusterIssuer – Argo CD Application-ök
# (platform projekt)
# -----------------------------------------------------------------------------

variable "acme_email" {
  description = "A Let's Encrypt értesítési címe."
  type        = string
  default     = "platformengineer@vighsandor.hu"
}

variable "acme_server" {
  description = "Az ACME-végpont. Alapértelmezés: Let's Encrypt staging (bőkezű rate limit)."
  type        = string
  default     = "https://acme-staging-v02.api.letsencrypt.org/directory"
}

locals {
  app_cert_manager = {
    project   = local.argocd_project_platform
    namespace = "cert-manager"
    repo_url  = "https://charts.jetstack.io"
    chart     = "cert-manager"
    revision  = "v1.19.4"
    values = yamlencode({
      crds       = { enabled = true }
      prometheus = { enabled = false }
    })
    sync_options = ["ServerSideApply=true", "RespectIgnoreDifferences=true"]
    # A webhook namespaceSelectorát a Kubernetes (egy mutating webhook) utólag
    # kiegészíti. Enélkül az Argo CD folyamatosan eltérést (OutOfSync) látna.
    ignore_differences = yamlencode([{
      group        = "admissionregistration.k8s.io"
      kind         = "ValidatingWebhookConfiguration"
      name         = "cert-manager-webhook"
      jsonPointers = ["/webhooks/0/namespaceSelector/matchExpressions"]
    }])
  }

  # A ClusterIssuer sima Kubernetes-erőforrás (nem chart), ezért a bedag/raw
  # "csomagoló" chart telepíti. A CRD-jét a cert-manager hozza: amíg az nincs
  # kész, a szinkron hibát ad, és az Argo CD újrapróbálja (retry).
  app_cluster_issuer = {
    project   = local.argocd_project_platform
    namespace = "cert-manager"
    repo_url  = "https://bedag.github.io/helm-charts"
    chart     = "raw"
    revision  = "2.0.2"
    values = yamlencode({
      resources = [{
        apiVersion = "cert-manager.io/v1"
        kind       = "ClusterIssuer"
        metadata   = { name = "letsencrypt" }
        spec = {
          acme = {
            email               = var.acme_email
            server              = var.acme_server
            privateKeySecretRef = { name = "letsencrypt-account-key" }
            solvers             = [{ http01 = { ingress = {} } }]
          }
        }
      }]
    })
    sync_options       = ["SkipDryRunOnMissingResource=true"]
    ignore_differences = yamlencode([])
  }
}
