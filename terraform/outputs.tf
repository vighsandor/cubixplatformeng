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

output "argocd_url" {
  description = "Az Argo CD felülete: belépés az Entra ID-fiókkal (LOG IN VIA ENTRA ID)."
  value       = local.argocd_url
}

output "argocd_entra_app" {
  description = "Az Argo CD Entra ID-alkalmazása (App registrations)."
  value       = "${azuread_application.argocd.display_name} (client ID: ${azuread_application.argocd.client_id})"
}

output "request" {
  description = "Az igénylés adatai (tfvars: request)."
  value       = terraform_data.request.output
}
