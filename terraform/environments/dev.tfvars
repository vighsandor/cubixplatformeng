# =============================================================================
# A(z) project-x dev környezet bemenetei (igénylés: lásd a pull requestet)
# Workspace: dev   –   a fájl neve, az env_name és a workspace neve egyezik
# =============================================================================

project_name = "project-x"
env_name     = "dev"
expires      = "2027-02-21"

# Hálózat: környezetenként saját, át nem fedő /12
vnet_address_space = "10.240.0.0/12"
node_subnet_prefix = "10.240.0.0/24"

# Hozzáférés: ember által olvasható név => Entra ID UPN
# (az object ID-t a Terraform keresi ki, lásd entra.tf)
platform_admins = {
  vighsandor = "platformengineer_vighsandor.hu#EXT#@platformengineervighsandor.onmicrosoft.com"
}
platform_admin_service_principals = {
  github-actions = "github-repos" # a pipeline identitása: a Helm-telepítéshez kell a cluster-admin jog
}
developers = {
  vighsandor = "platformengineer_vighsandor.hu#EXT#@platformengineervighsandor.onmicrosoft.com"
}
readers = {
  vighsandor = "platformengineer_vighsandor.hu#EXT#@platformengineervighsandor.onmicrosoft.com"
}
