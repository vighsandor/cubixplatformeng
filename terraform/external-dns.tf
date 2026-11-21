# -----------------------------------------------------------------------------
# External DNS: identitás (managed identity + workload identity federation +
# legkisebb jogosultság a saját alzónán) és a telepítése a clusterbe
# -----------------------------------------------------------------------------

locals {
  external_dns_namespace       = "external-dns"
  external_dns_service_account = "external-dns"
}

resource "azurerm_user_assigned_identity" "external_dns" {
  name                = "${local.resource_basename}-externaldns"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  tags                = local.common_tags
}

# Az external-dns service account titok nélkül, ezzel az identitással jelentkezik be
resource "azurerm_federated_identity_credential" "external_dns" {
  name                      = "external-dns"
  user_assigned_identity_id = azurerm_user_assigned_identity.external_dns.id
  issuer                    = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  subject                   = "system:serviceaccount:${local.external_dns_namespace}:${local.external_dns_service_account}"
  audience                  = ["api://AzureADTokenExchange"]
}

resource "azurerm_role_assignment" "external_dns_zone_contributor" {
  scope                = azurerm_dns_zone.env.id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.external_dns.principal_id
  principal_type       = "ServicePrincipal"
}

# A values már nem kézzel kitöltött sablonból jön: minden érték közvetlenül a
# Terraform-erőforrásokból származik, így nem lehet elgépelni vagy elavult
# azonosítót használni.
resource "helm_release" "external_dns" {
  name             = "external-dns"
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  chart            = "external-dns"
  version          = "1.20.0"
  namespace        = local.external_dns_namespace
  create_namespace = true

  values = [yamlencode({
    logFormat = "text"
    podLabels = { "azure.workload.identity/use" = "true" }

    sources            = ["ingress"]
    provider           = { name = "azure" }
    policy             = "sync"
    registry           = "txt"
    triggerLoopOnEvent = true

    txtOwnerId    = replace(azurerm_dns_zone.env.name, ".", "-")
    domainFilters = [azurerm_dns_zone.env.name]

    serviceAccount = {
      name        = local.external_dns_service_account
      annotations = { "azure.workload.identity/client-id" = azurerm_user_assigned_identity.external_dns.client_id }
    }
    secretConfiguration = {
      enabled   = true
      mountPath = "/etc/kubernetes"
      data = {
        "azure.json" = jsonencode({
          subscriptionId               = data.azurerm_client_config.current.subscription_id
          resourceGroup                = azurerm_resource_group.aks.name # az identitás resource groupja
          useWorkloadIdentityExtension = true
        })
      }
    }
    extraArgs = ["--azure-resource-group=${azurerm_resource_group.dns.name}"] # a DNS-zóna resource groupja
  })]

  depends_on = [
    time_sleep.rbac_propagation,
    azurerm_federated_identity_credential.external_dns,
    azurerm_role_assignment.external_dns_zone_contributor,
    azurerm_dns_ns_record.delegation,
  ]
}
