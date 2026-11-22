# -----------------------------------------------------------------------------
# Argo CD: telepítés, Entra ID-bejelentkezés, projektek és az alkalmazások
#
# A Terraform innentől csak az Argo CD-t telepíti közvetlenül (Helm). A
# platformkomponenseket (Traefik, External DNS, cert-manager, ClusterIssuer) és
# a demóalkalmazást Argo CD Application-ök írják le; ezeket a Terraform a
# bedag/raw "csomagoló" charttal hozza létre az argocd namespace-ben. Az Argo
# CD folyamatosan összeveti a kívánt és a valós állapotot (drift detection),
# és automatikusan vissza is állítja (AutoSync + selfHeal).
# -----------------------------------------------------------------------------

variable "argocd_admin_enabled" {
  description = "Él-e a helyi admin fiók (vészhelyzeti belépés). Alapból kikapcsolva: a belépés Entra ID-vel történik."
  type        = bool
  default     = false
}

locals {
  argocd_namespace = "argocd"
  argocd_hostname  = "argocd.${azurerm_dns_zone.env.name}"
  argocd_url       = "https://${local.argocd_hostname}"

  # A projektek nevei: a platform a közös infrastruktúra, a product a
  # fejlesztők alkalmazásai
  argocd_project_platform = "platform"
  argocd_project_product  = "product"

  # A platformkomponensek namespace-ei: a product projekt ezekbe nem telepíthet
  platform_namespaces = ["argocd", "kube-system", "ingress-controller", "external-dns", "cert-manager"]
}

# --- Entra ID-bejelentkezés -----------------------------------------------------
# App registration az Argo CD-nek. Titkos kulcs nincs: az argocd-server workload
# identityvel (federated credential) igazolja magát az Entra ID felé.

locals {
  # Az alkalmazás tulajdonosai: a platformadminok és a pipeline identitása
  # (a pipeline-nak tulajdonosként kell kezelnie a federated credentialt)
  argocd_app_owners = concat(
    [for upn in values(var.platform_admins) : data.azuread_user.member[upn].object_id],
    [for sp in values(var.platform_admin_service_principals) : data.azuread_service_principal.member[sp].object_id],
  )
}

resource "azuread_application" "argocd" {
  display_name     = "${local.resource_basename}-argocd"
  sign_in_audience = "AzureADMyOrg"
  owners           = local.argocd_app_owners

  # A tokenbe kerüljenek bele a felhasználó biztonsági csoportjai: az Argo CD
  # RBAC ezek alapján osztja ki a szerepköröket (lásd lent: policy.csv)
  group_membership_claims = ["SecurityGroup"]

  web {
    redirect_uris = ["${local.argocd_url}/auth/callback"]
  }

  # Az argocd CLI bejelentkezése (argocd login --sso)
  public_client {
    redirect_uris = ["http://localhost:8085/auth/callback"]
  }

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read (delegated)
      type = "Scope"
    }
  }
}

# Az Entra ID-alkalmazás tenantbeli példányát (service principal, "Enterprise
# application") NEM a Terraform hozza létre: az Application Developer
# szerepkörrel a pipeline nem tudja kezelni (módosítani, törölni) – 403
# Authorization_RequestDenied. A példányt az Entra ID az első belépéskor, a
# hozzájáruláskor (consent) magától létrehozza, és az alkalmazás törlésekor
# vele együtt törli. (A korábban létrehozottat lásd: migracio.tf.)

resource "azuread_application_federated_identity_credential" "argocd" {
  application_id = azuread_application.argocd.id
  display_name   = "argocd-server"
  description    = "Az argocd-server service account workload identityje (${local.resource_basename})"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  subject        = "system:serviceaccount:${local.argocd_namespace}:argocd-server"
}

# --- Argo CD telepítése -----------------------------------------------------------

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "10.18.2"
  namespace        = local.argocd_namespace
  create_namespace = true

  # sikertelen telepítésnél a Helm visszagörgeti és feltakarítja a release-t
  atomic          = true
  cleanup_on_fail = true

  values = [yamlencode({
    global = { domain = local.argocd_hostname }

    # A Dex-re nincs szükség: az Argo CD közvetlenül az Entra ID-hez fordul (OIDC)
    dex = { enabled = false }

    configs = {
      # A TLS-t a Traefik zárja le, az argocd-server mögötte HTTP-n fut
      params = { "server.insecure" = true }

      cm = {
        "admin.enabled" = var.argocd_admin_enabled
        "oidc.config" = yamlencode({
          name                   = "Entra ID"
          issuer                 = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/v2.0"
          clientID               = azuread_application.argocd.client_id
          azure                  = { useWorkloadIdentity = true }
          requestedIDTokenClaims = { groups = { essential = true } }
          requestedScopes        = ["openid", "profile", "email"]
        })
      }

      # Jogosultság csak a környezet Entra ID-csoportjain keresztül (object ID):
      #  - platform-admins: admin (minden)
      #  - developers: mindent láthat, a product projektben alkalmazást
      #    létrehozhat, módosíthat, szinkronizálhat, törölhet, és láthatja a logokat
      #  - readers: csak olvasás
      # Aki egyik csoportnak sem tagja, be tud lépni, de semmit nem lát.
      rbac = {
        "policy.default" = ""
        "scopes"         = "[groups]"
        "policy.csv"     = <<-EOT
          p, role:developer, applications, *, ${local.argocd_project_product}/*, allow
          p, role:developer, logs, get, ${local.argocd_project_product}/*, allow
          g, role:developer, role:readonly
          g, ${azuread_group.env["platform_admins"].object_id}, role:admin
          g, ${azuread_group.env["developers"].object_id}, role:developer
          g, ${azuread_group.env["readers"].object_id}, role:readonly
        EOT
      }
    }

    server = {
      # Workload identity: a tokent az Entra ID-tól titok nélkül kapja
      podLabels = { "azure.workload.identity/use" = "true" }
      serviceAccount = {
        annotations = { "azure.workload.identity/client-id" = azuread_application.argocd.client_id }
      }

      ingress = {
        enabled          = true
        ingressClassName = "traefik"
        annotations      = { "cert-manager.io/cluster-issuer" = "letsencrypt" }
        tls              = true # a tanúsítványt a cert-manager teszi az argocd-server-tls secretbe
      }
    }
  })]

  depends_on = [
    time_sleep.rbac_propagation,
    azuread_application_federated_identity_credential.argocd,
  ]
}

# --- Projektek ----------------------------------------------------------------------
# platform: a közös infrastruktúra (cluster-szintű erőforrásokkal)
# product: a fejlesztők alkalmazásai (a platform namespace-eibe nem telepíthet)

resource "helm_release" "argocd_projects" {
  name       = "argocd-projects"
  repository = "https://bedag.github.io/helm-charts"
  chart      = "raw"
  version    = "2.0.2"
  namespace  = local.argocd_namespace

  atomic          = true
  cleanup_on_fail = true

  values = [yamlencode({
    resources = [
      {
        apiVersion = "argoproj.io/v1alpha1"
        kind       = "AppProject"
        metadata   = { name = local.argocd_project_platform, namespace = local.argocd_namespace }
        spec = {
          description = "Platformkomponensek: ingress, DNS, tanúsítványok (${local.resource_basename})"
          sourceRepos = [
            "https://traefik.github.io/charts",
            "https://kubernetes-sigs.github.io/external-dns/",
            "https://charts.jetstack.io",
            "https://bedag.github.io/helm-charts",
          ]
          destinations = [
            for ns in local.platform_namespaces : { server = "https://kubernetes.default.svc", namespace = ns }
            if ns != local.argocd_namespace
          ]
          # CRD-k, ClusterRole-ok, webhookok, IngressClass, ClusterIssuer
          clusterResourceWhitelist = [{ group = "*", kind = "*" }]
        }
      },
      {
        apiVersion = "argoproj.io/v1alpha1"
        kind       = "AppProject"
        metadata   = { name = local.argocd_project_product, namespace = local.argocd_namespace }
        spec = {
          description = "A fejlesztők alkalmazásai (${local.resource_basename})"
          sourceRepos = ["oci://docker.io/ecklm/*", "https://github.com/vighsandor/*"]
          destinations = concat(
            [for ns in local.platform_namespaces : { server = "https://kubernetes.default.svc", namespace = "!${ns}" }],
            [{ server = "https://kubernetes.default.svc", namespace = "*" }],
          )
          # cluster-szintű erőforrásból csak namespace-t hozhat létre
          clusterResourceWhitelist = [{ group = "", kind = "Namespace" }]
        }
      },
    ]
  })]

  depends_on = [helm_release.argocd]
}

# --- Application-ök -----------------------------------------------------------------
# Az egyes komponensek leírása a saját fájljukban van (ingress.tf,
# external-dns.tf, cert-manager.tf, demo-app.tf); itt egységes formában
# Application-ökké alakítom őket. Minden Application:
#  - a platform vagy a product projektben van,
#  - AutoSync (prune + selfHeal), újrapróbálással: a CRD-kre váró alkalmazások
#    (pl. a ClusterIssuer a cert-manager CRD-jére) maguktól beállnak,
#  - finalizerrel: az Application törlésekor az Argo CD a létrehozott
#    erőforrásokat is törli,
#  - Terraform-szinten az Argo CD-től és a projektektől függ.

locals {
  # Minden komponens leírása azonos szerkezetű (lásd local.app_*), így egyetlen
  # erőforrás-blokk kezeli mindet. A values és az ignoreDifferences YAML-szöveg,
  # hogy a különböző szerkezetű beállítások is egy típusba férjenek.
  argocd_applications = {
    for name, app in tomap({
      "traefik"        = local.app_traefik
      "external-dns"   = local.app_external_dns
      "cert-manager"   = local.app_cert_manager
      "cluster-issuer" = local.app_cluster_issuer
      "colors"         = local.app_colors
    }) : name => app if name != "colors" || var.demo_app_enabled
  }
}

# A finalizer kétélű fegyver: ha az Argo CD-t előbb törlöm, mint az
# Application-öket, a finalizerek a végtelenségig várnak (nincs, aki
# feldolgozza őket), és kézzel kell takarítani. A lebontás sorrendje ezért:
# Application-ök -> várakozás (az Argo CD letörli az erőforrásaikat) -> projektek
# -> Argo CD. Létrehozáskor ez a várakozás nem lassít (create_duration nincs).
resource "time_sleep" "argocd_app_cleanup" {
  destroy_duration = "120s"

  depends_on = [
    helm_release.argocd,
    helm_release.argocd_projects,
  ]
}

resource "helm_release" "argocd_app" {
  for_each   = local.argocd_applications
  name       = "argocd-app-${each.key}"
  repository = "https://bedag.github.io/helm-charts"
  chart      = "raw"
  version    = "2.0.2"
  namespace  = local.argocd_namespace

  atomic          = true
  cleanup_on_fail = true

  values = [yamlencode({
    resources = [{
      apiVersion = "argoproj.io/v1alpha1"
      kind       = "Application"
      metadata = {
        name       = each.key
        namespace  = local.argocd_namespace
        finalizers = ["resources-finalizer.argocd.argoproj.io"]
      }
      spec = {
        project = each.value.project
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = each.value.namespace
        }
        source = merge(
          {
            repoURL        = each.value.repo_url
            targetRevision = each.value.revision
            helm           = { valuesObject = yamldecode(each.value.values) }
          },
          each.value.chart != "" ? { chart = each.value.chart } : { path = "." },
        )
        ignoreDifferences = yamldecode(each.value.ignore_differences)
        syncPolicy = {
          automated   = { enabled = true, prune = true, selfHeal = true }
          syncOptions = concat(["CreateNamespace=true"], each.value.sync_options)
          retry = {
            limit   = 10
            backoff = { duration = "15s", factor = 2, maxDuration = "5m" }
          }
        }
      }
    }]
  })]

  depends_on = [
    helm_release.argocd,
    helm_release.argocd_projects,
    time_sleep.argocd_app_cleanup, # lebontáskor: előbb az Application-ök, utána a várakozás
  ]
}
