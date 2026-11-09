# -----------------------------------------------------------------------------
# DNS: a környezet alzónája, NS-delegáció a szülőzónában, valamint az
# External DNS identitása (managed identity + federated credential + jog)
# -----------------------------------------------------------------------------

variable "parent_zone_name" {
  description = "A szülő (alap) DNS-zóna neve."
  type        = string
  default     = "vighsandor.az.cubix-pe.hu"
}

variable "parent_zone_resource_group" {
  description = "A szülőzóna resource groupja (nem ez a kód kezeli)."
  type        = string
  default     = "course-baseline"
}

locals {
  child_zone_label = "${var.project_name}.${var.env_name}"
  child_zone_name  = "${local.child_zone_label}.${var.parent_zone_name}"
}

# A szülőzóna a course-baseline része, ezt a kód csak olvassa
data "azurerm_dns_zone" "parent" {
  name                = var.parent_zone_name
  resource_group_name = var.parent_zone_resource_group
}

resource "azurerm_resource_group" "dns" {
  name     = "${local.resource_basename}-dns"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_dns_zone" "env" {
  name                = local.child_zone_name
  resource_group_name = azurerm_resource_group.dns.name
  tags                = local.common_tags
}

# A portál a "child of an existing zone" opcióval ezt automatikusan elvégezte
resource "azurerm_dns_ns_record" "delegation" {
  name                = local.child_zone_label
  zone_name           = data.azurerm_dns_zone.parent.name
  resource_group_name = data.azurerm_dns_zone.parent.resource_group_name
  ttl                 = 3600
  records             = azurerm_dns_zone.env.name_servers
  tags                = local.common_tags
}

# --- External DNS identitás --------------------------------------------------

resource "azurerm_user_assigned_identity" "external_dns" {
  name                = "${local.resource_basename}-externaldns"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  tags                = local.common_tags
}

# Workload identity federation: az external-dns namespace external-dns
# service accountja titok nélkül, ezzel az identitással jelentkezik be
resource "azurerm_federated_identity_credential" "external_dns" {
  name                      = "external-dns"
  user_assigned_identity_id = azurerm_user_assigned_identity.external_dns.id
  issuer                    = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  subject                   = "system:serviceaccount:external-dns:external-dns"
  audience                  = ["api://AzureADTokenExchange"]
}

# Legkisebb jogosultság: csak a saját alzónán
resource "azurerm_role_assignment" "external_dns_zone_contributor" {
  scope                = azurerm_dns_zone.env.id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.external_dns.principal_id
  principal_type       = "ServicePrincipal"
}
