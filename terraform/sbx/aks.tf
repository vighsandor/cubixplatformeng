# -----------------------------------------------------------------------------
# AKS cluster, a cluster identitása és a hozzáférés (Entra ID-csoportok + RBAC)
# -----------------------------------------------------------------------------

variable "kubernetes_version" {
  description = "Kubernetes-verzió (minden környezetben ugyanaz)."
  type        = string
  default     = "1.36.3"
}

variable "node_vm_size" {
  description = "A system node pool VM-mérete."
  type        = string
  default     = "Standard_D2as_v5"
}

variable "additional_platform_admin_object_ids" {
  description = "További platformadminok Entra ID object ID-i (a futtató identitás mindig tag)."
  type        = list(string)
  default     = []
}

variable "developer_object_ids" {
  description = "Írási jogot kapó fejlesztők Entra ID object ID-i (igénylőlap 5. pont)."
  type        = list(string)
  default     = []
}

variable "reader_object_ids" {
  description = "Olvasási jogot kapó személyek Entra ID object ID-i (igénylőlap 5. pont)."
  type        = list(string)
  default     = []
}

resource "azurerm_resource_group" "aks" {
  name     = "${local.resource_basename}-aks"
  location = var.location
  tags     = local.common_tags
}

# A cluster (control plane) identitása. Saját VNet mellett előre kell létrehozni,
# hogy a cluster létrehozása előtt jogot kaphasson az alhálózaton.
resource "azurerm_user_assigned_identity" "aks" {
  name                = "${local.resource_basename}-aks"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  tags                = local.common_tags
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = local.resource_basename
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  dns_prefix          = "${local.resource_basename}-dns"
  node_resource_group = "${azurerm_resource_group.aks.name}-nodes"

  kubernetes_version        = var.kubernetes_version
  sku_tier                  = "Free"
  automatic_upgrade_channel = null # = none: a frissítést kézben tartom
  node_os_upgrade_channel   = "None"

  node_provisioning_profile {
    mode = "Manual"
  }

  default_node_pool {
    name           = "system"
    node_count     = 1
    vm_size        = var.node_vm_size
    os_sku         = "Ubuntu"
    vnet_subnet_id = azurerm_subnet.aks_nodes.id
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    service_cidr        = "10.0.0.0/16"
    dns_service_ip      = "10.0.0.10"
  }

  # Entra ID-hitelesítés Azure RBAC jogosultságkezeléssel, helyi fiókok nélkül
  role_based_access_control_enabled = true
  azure_active_directory_role_based_access_control {
    tenant_id              = data.azurerm_client_config.current.tenant_id
    admin_group_object_ids = []
    azure_rbac_enabled     = true
  }
  local_account_disabled = true

  # Workload identity federation (External DNS) előfeltételei
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  tags = local.common_tags

  depends_on = [azurerm_role_assignment.aks_subnet_network_contributor]
}

# --- Entra ID-csoportok ------------------------------------------------------

resource "azuread_group" "platform_admins" {
  display_name     = "${local.resource_basename}-platform-admins"
  description      = "${var.project_name} ${var.env_name} környezet platformadminjai"
  security_enabled = true
}

resource "azuread_group" "developers" {
  display_name     = "${local.resource_basename}-developers"
  description      = "${var.project_name} ${var.env_name} környezet fejlesztői (írás)"
  security_enabled = true
}

resource "azuread_group" "readers" {
  count            = local.readers_enabled ? 1 : 0
  display_name     = "${local.resource_basename}-readers"
  description      = "${var.project_name} ${var.env_name} környezet olvasói"
  security_enabled = true
}

locals {
  platform_admins = toset(concat(
    [data.azurerm_client_config.current.object_id],
    var.additional_platform_admin_object_ids,
  ))

  readers_enabled = length(var.reader_object_ids) > 0

  # csoport kulcsa => object ID
  aks_groups = {
    platform_admins = azuread_group.platform_admins.object_id
    developers      = azuread_group.developers.object_id
    readers         = one(azuread_group.readers[*].object_id) # null, ha nincs olvasócsoport
  }

  # Csoport–szerepkör párok a clusteren (az olvasói párok csak, ha van olvasó).
  # A szűrés változóra épül, így a for_each kulcsai már plan-időben ismertek.
  aks_role_assignments = {
    for k, v in {
      "platform_admins-cluster_admin" = { group = "platform_admins", role = "Azure Kubernetes Service RBAC Cluster Admin" }
      "platform_admins-cluster_user"  = { group = "platform_admins", role = "Azure Kubernetes Service Cluster User Role" }
      "developers-writer"             = { group = "developers", role = "Azure Kubernetes Service RBAC Writer" }
      "developers-cluster_user"       = { group = "developers", role = "Azure Kubernetes Service Cluster User Role" }
      "readers-reader"                = { group = "readers", role = "Azure Kubernetes Service RBAC Reader" }
      "readers-cluster_user"          = { group = "readers", role = "Azure Kubernetes Service Cluster User Role" }
    } : k => v if v.group != "readers" || local.readers_enabled
  }
}

resource "azuread_group_member" "platform_admins" {
  for_each         = local.platform_admins
  group_object_id  = azuread_group.platform_admins.object_id
  member_object_id = each.key
}

resource "azuread_group_member" "developers" {
  for_each         = toset(var.developer_object_ids)
  group_object_id  = azuread_group.developers.object_id
  member_object_id = each.key
}

resource "azuread_group_member" "readers" {
  for_each         = toset(var.reader_object_ids)
  group_object_id  = azuread_group.readers[0].object_id
  member_object_id = each.key
}

# Jogosultság csak csoportnak, személynek soha
resource "azurerm_role_assignment" "aks" {
  for_each             = local.aks_role_assignments
  scope                = azurerm_kubernetes_cluster.aks.id
  role_definition_name = each.value.role
  principal_id         = local.aks_groups[each.value.group]
  principal_type       = "Group"
}
