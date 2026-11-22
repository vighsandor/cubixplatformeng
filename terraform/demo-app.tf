# -----------------------------------------------------------------------------
# Demóalkalmazás (füstteszt) – Argo CD Application a product projektben.
# Igazolja, hogy a teljes lánc működik:
# Ingress -> External DNS -> DNS-rekord -> Traefik -> TLS (cert-manager) -> Pod
# -----------------------------------------------------------------------------

variable "demo_app_enabled" {
  description = "Települjön-e a colors demóalkalmazás."
  type        = bool
  default     = true
}

locals {
  app_colors = {
    project   = local.argocd_project_product
    namespace = "colors"
    repo_url  = "oci://docker.io/ecklm/colors-demo-app"
    chart     = "" # OCI-forrásnál a chart a repó gyökerében van (path: .)
    revision  = "1.0.0"
    values = yamlencode({
      ingress = {
        host        = "colors.${azurerm_dns_zone.env.name}"
        annotations = { "cert-manager.io/cluster-issuer" = "letsencrypt" }
      }
    })
    sync_options       = []
    ignore_differences = yamlencode([])
  }
}
