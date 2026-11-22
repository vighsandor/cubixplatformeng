# -----------------------------------------------------------------------------
# Ingress controller: Traefik – Argo CD Application (platform projekt)
# A telepítést az Argo CD végzi (argocd.tf: helm_release.argocd_app["traefik"]).
# -----------------------------------------------------------------------------

locals {
  app_traefik = {
    project   = local.argocd_project_platform
    namespace = "ingress-controller"
    repo_url  = "https://traefik.github.io/charts"
    chart     = "traefik"
    revision  = "41.2.0"
    values = yamlencode({
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
    })
    # A Traefik CRD-i nagyok: kliensoldali apply-jal túllépnék az annotáció
    # méretkorlátját, ezért szerveroldali apply
    sync_options       = ["ServerSideApply=true"]
    ignore_differences = yamlencode([])
  }
}
