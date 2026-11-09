# -----------------------------------------------------------------------------
# Hálózat: saját VNet és alhálózat az AKS node-jainak
# A portál ezt "Create new"-val, menet közben hozta létre; Terraformban külön
# erőforrás, mert később más erőforrásokkal is megosztható.
# -----------------------------------------------------------------------------

variable "vnet_address_space" {
  description = "A környezet saját, át nem fedő /12 VNet-tartománya."
  type        = string
}

variable "node_subnet_prefix" {
  description = "A node-alhálózat tartománya (a VNet-tartományon belül)."
  type        = string
}

resource "azurerm_virtual_network" "aks" {
  name                = "${local.resource_basename}-network"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  address_space       = [var.vnet_address_space]
  tags                = local.common_tags
}

resource "azurerm_subnet" "aks_nodes" {
  name                 = "${local.resource_basename}-aks-nodes"
  resource_group_name  = azurerm_resource_group.aks.name
  virtual_network_name = azurerm_virtual_network.aks.name
  address_prefixes     = [var.node_subnet_prefix]
}

# A portál ezt automatikusan elvégezte: a cluster identitásának joga kell az
# alhálózathoz, hogy a node-okat és a load balancert bekösse.
resource "azurerm_role_assignment" "aks_subnet_network_contributor" {
  scope                = azurerm_subnet.aks_nodes.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
  principal_type       = "ServicePrincipal"
}
