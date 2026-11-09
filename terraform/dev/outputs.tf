# -----------------------------------------------------------------------------
# Kimenetek: ezeket használja a létrehozó script a Kubernetesen belüli
# (kézi, Helm-es) lépésekhez és az átadó üzenethez
# -----------------------------------------------------------------------------

output "subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "aks_resource_group" {
  value = azurerm_resource_group.aks.name
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "aks_oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.aks.oidc_issuer_url
}

output "dns_resource_group" {
  value = azurerm_resource_group.dns.name
}

output "dns_zone_name" {
  value = azurerm_dns_zone.env.name
}

output "dns_zone_name_servers" {
  value = azurerm_dns_zone.env.name_servers
}

output "external_dns_identity_name" {
  value = azurerm_user_assigned_identity.external_dns.name
}

output "external_dns_client_id" {
  value = azurerm_user_assigned_identity.external_dns.client_id
}

output "external_dns_txt_owner_id" {
  value = replace(azurerm_dns_zone.env.name, ".", "-")
}

output "platform_admins_group" {
  value = azuread_group.platform_admins.display_name
}

output "developers_group" {
  value = azuread_group.developers.display_name
}
