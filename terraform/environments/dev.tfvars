# =============================================================================
# A(z) project-x dev környezet bemenetei (az igénylés adatai: request)
# Workspace: dev   –   a fájl neve, az env_name és a workspace neve egyezik
# =============================================================================

project_name = "project-x"
env_name     = "dev"
expires      = "2027-02-21"

# Az igénylés (a korábbi igénylőlap helyett: minden egy helyen, a Terraform
# ellenőrzi és a state-ben is rögzíti – terraform_data.request)
request = {
  requester = "platformengineer_vighsandor.hu#EXT#@platformengineervighsandor.onmicrosoft.com"
  team      = "Project X"
  reason    = "Közös fejlesztői környezet a Project X csapatnak; az alkalmazásainkat Argo CD-vel, a product projektbe telepítjük."
  approver  = "Cubix Platform Engineering kurzus"
}

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
