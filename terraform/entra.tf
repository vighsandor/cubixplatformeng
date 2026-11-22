# -----------------------------------------------------------------------------
# Entra ID: a környezet csoportjai és tagjaik
#
# A csoportok nem az AKS-hez tartoznak, hanem a környezethez: ma az AKS-en
# kapnak jogot (aks.tf), de bármi másra is kioszthatók. A tagokat ember által
# olvasható néven és UPN-nel adom meg; az object ID-t a Terraform keresi ki.
# -----------------------------------------------------------------------------

variable "platform_admins" {
  description = "Platformadminok: név => Entra ID UPN."
  type        = map(string)
}

variable "developers" {
  description = "Írási jogú fejlesztők: név => Entra ID UPN (a tfvars-ban, a request blokk mellett)."
  type        = map(string)
  default     = {}
}

variable "readers" {
  description = "Olvasási jogú tagok: név => Entra ID UPN (a tfvars-ban, a request blokk mellett)."
  type        = map(string)
  default     = {}
}

variable "platform_admin_service_principals" {
  description = "Gépi platformadminok, pl. a pipeline identitása: név => service principal megjelenített neve."
  type        = map(string)
  default     = {}
}

locals {
  groups = {
    platform_admins = { suffix = "platform-admins", description = "platformadminjai" }
    developers      = { suffix = "developers", description = "fejlesztői (írás)" }
    readers         = { suffix = "readers", description = "olvasói" }
  }

  # "csoport/név" => tag object ID-ja. A kulcsok a változók kulcsaiból jönnek,
  # így plan-időben ismertek, és a plan ember által olvasható nevet mutat.
  group_members = merge(
    { for name, upn in var.platform_admins : "platform_admins/${name}" => { group = "platform_admins", object_id = data.azuread_user.member[upn].object_id } },
    { for name, upn in var.developers : "developers/${name}" => { group = "developers", object_id = data.azuread_user.member[upn].object_id } },
    { for name, upn in var.readers : "readers/${name}" => { group = "readers", object_id = data.azuread_user.member[upn].object_id } },
    { for name, sp in var.platform_admin_service_principals : "platform_admins/sp:${name}" => { group = "platform_admins", object_id = data.azuread_service_principal.member[sp].object_id } },
  )
}

data "azuread_user" "member" {
  for_each            = toset(concat(values(var.platform_admins), values(var.developers), values(var.readers)))
  user_principal_name = each.key
}

data "azuread_service_principal" "member" {
  for_each     = toset(values(var.platform_admin_service_principals))
  display_name = each.key
}

resource "azuread_group" "env" {
  for_each         = local.groups
  display_name     = "${local.resource_basename}-${each.value.suffix}"
  description      = "${var.project_name} ${var.env_name} környezet ${each.value.description}"
  security_enabled = true
}

resource "azuread_group_member" "env" {
  for_each         = local.group_members
  group_object_id  = azuread_group.env[each.value.group].object_id
  member_object_id = each.value.object_id
}
