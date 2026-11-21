# -----------------------------------------------------------------------------
# cert-manager és a Let's Encrypt ClusterIssuer
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

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.19.4"
  namespace        = "cert-manager"
  create_namespace = true

  values = [yamlencode({
    crds       = { enabled = true }
    prometheus = { enabled = false }
  })]

  depends_on = [time_sleep.rbac_propagation]
}

# A ClusterIssuer sima Kubernetes-erőforrás (nem chart). A helm providerrel a
# bedag/raw "csomagoló" charton keresztül telepítem, így nem kell hozzá külön
# kubernetes provider.
resource "helm_release" "cluster_issuer" {
  name       = "cluster-issuer"
  repository = "https://bedag.github.io/helm-charts"
  chart      = "raw"
  version    = "2.0.2"
  namespace  = "cert-manager"

  values = [yamlencode({
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
  })]

  depends_on = [helm_release.cert_manager] # a ClusterIssuer CRD-jét a cert-manager hozza
}
