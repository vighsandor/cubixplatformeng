# -----------------------------------------------------------------------------
# Ingress controller: Traefik (az 1. hét kézi helm parancsa Terraformban)
# -----------------------------------------------------------------------------

resource "helm_release" "traefik" {
  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = "41.2.0"
  namespace        = "ingress-controller"
  create_namespace = true

  values = [yamlencode({
    service = {
      annotations = {
        # az Azure Load Balancer ezen az útvonalon ellenőrzi a Traefik egészségét
        "service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path" = "/healthz"
      }
    }
    ports = {
      web = {
        http = {
          # minden HTTP kérés HTTPS-re irányítva: a TLS kötelező
          redirections = {
            entryPoint = { to = "websecure", scheme = "https", permanent = true }
          }
        }
      }
    }
  })]

  depends_on = [time_sleep.rbac_propagation]
}
