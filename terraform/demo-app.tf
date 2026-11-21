# -----------------------------------------------------------------------------
# Demóalkalmazás (füstteszt): igazolja, hogy a teljes lánc működik
# Ingress -> External DNS -> DNS-rekord -> Traefik -> TLS (cert-manager) -> Pod
# -----------------------------------------------------------------------------

variable "demo_app_enabled" {
  description = "Települjön-e a colors demóalkalmazás."
  type        = bool
  default     = true
}

resource "helm_release" "demo_app" {
  count            = var.demo_app_enabled ? 1 : 0
  name             = "colors"
  repository       = "oci://docker.io/ecklm"
  chart            = "colors-demo-app"
  namespace        = "colors"
  create_namespace = true

  values = [yamlencode({
    ingress = {
      host        = "colors.${azurerm_dns_zone.env.name}"
      annotations = { "cert-manager.io/cluster-issuer" = "letsencrypt" }
    }
  })]

  depends_on = [
    helm_release.traefik,
    helm_release.external_dns,
    helm_release.cluster_issuer,
  ]
}
