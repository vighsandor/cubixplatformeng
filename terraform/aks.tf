# -----------------------------------------------------------------------------
# AKS cluster, a cluster identitása, és a csoportok jogai a clusteren
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

variable "node_count" {
  description = "A system node pool node-jainak száma."
  type        = number
  default     = 1
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
    node_count     = var.node_count
    vm_size        = var.node_vm_size
    os_sku         = "Ubuntu"
    vnet_subnet_id = azurerm_subnet.aks_nodes.id

    # Az Azure a node pool létrehozásakor magától beállítja ezt az alapértéket
    # (max_surge = 10%). Ha a kódban nincs benne, minden plan "törölné", így a
    # változatlan kód is folyamatosan 1 módosítást mutatna. Az Azure-alapértéket rögzítem.
    upgrade_settings {
      max_surge = "10%"
    }
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

  depends_on = [
    azurerm_role_assignment.aks_subnet_network_contributor,
    terraform_data.workspace_guard,
  ]
}

# --- A csoportok jogai a clusteren (jog csak csoportnak, személynek soha) ----

locals {
  aks_role_assignments = {
    "platform_admins-cluster_admin" = { group = "platform_admins", role = "Azure Kubernetes Service RBAC Cluster Admin" }
    "platform_admins-cluster_user"  = { group = "platform_admins", role = "Azure Kubernetes Service Cluster User Role" }
    "developers-writer"             = { group = "developers", role = "Azure Kubernetes Service RBAC Writer" }
    "developers-cluster_user"       = { group = "developers", role = "Azure Kubernetes Service Cluster User Role" }
    "readers-reader"                = { group = "readers", role = "Azure Kubernetes Service RBAC Reader" }
    "readers-cluster_user"          = { group = "readers", role = "Azure Kubernetes Service Cluster User Role" }
  }
}

resource "azurerm_role_assignment" "aks" {
  for_each             = local.aks_role_assignments
  scope                = azurerm_kubernetes_cluster.aks.id
  role_definition_name = each.value.role
  principal_id         = azuread_group.env[each.value.group].object_id
  principal_type       = "Group"
}

# A pipeline identitása (github-repos) közvetlenül is megkapja a cluster-admin
# jogot. A csoporttagság egy új környezetnél nem elég neki: a pipeline az
# AKS-tokent a futás elején kéri (a GitHub OIDC-token csak percekig érvényes),
# amikor még nem tagja az épp most létrehozott csoportnak, így a token
# "groups" claimjéből hiányzik a csoport. A közvetlen szerepkör-hozzárendelést
# az Azure szerveroldalon értékeli ki, ezért ugyanabban a futásban működik.
resource "azurerm_role_assignment" "aks_pipeline" {
  for_each             = var.platform_admin_service_principals
  scope                = azurerm_kubernetes_cluster.aks.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azuread_service_principal.member[each.value].object_id
  principal_type       = "ServicePrincipal"
}

# Az RBAC-jog és a csoporttagság néhány perc alatt lép életbe. A Kubernetesen
# belüli telepítések (Helm) csak ezután indulnak, különben 403-at kapnának.
resource "time_sleep" "rbac_propagation" {
  create_duration = "180s"

  depends_on = [
    azurerm_role_assignment.aks,
    azurerm_role_assignment.aks_pipeline,
    azuread_group_member.env,
  ]
}
