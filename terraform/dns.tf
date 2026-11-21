# -----------------------------------------------------------------------------
# DNS: a környezet alzónája és az NS-delegáció a szülőzónában
# (a rekordokat az External DNS kezeli, lásd external-dns.tf)
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

resource "azurerm_dns_ns_record" "delegation" {
  name                = local.child_zone_label
  zone_name           = data.azurerm_dns_zone.parent.name
  resource_group_name = data.azurerm_dns_zone.parent.resource_group_name
  ttl                 = 3600
  records             = azurerm_dns_zone.env.name_servers
  tags                = local.common_tags
}
