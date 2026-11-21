# -----------------------------------------------------------------------------
# Kimenetek: az átadó üzenethez és a hibakereséshez
# -----------------------------------------------------------------------------

output "environment" {
  value = terraform.workspace
}

output "aks_resource_group" {
  value = azurerm_resource_group.aks.name
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "dns_zone_name" {
  value = azurerm_dns_zone.env.name
}

output "groups" {
  value = { for k, g in azuread_group.env : k => g.display_name }
}

output "demo_url" {
  value = var.demo_app_enabled ? "https://colors.${azurerm_dns_zone.env.name}" : null
}

output "connect_commands" {
  value = <<-EOT
    az aks get-credentials -g ${azurerm_resource_group.aks.name} -n ${azurerm_kubernetes_cluster.aks.name} --overwrite-existing
    kubelogin convert-kubeconfig -l azurecli
  EOT
}
