# -----------------------------------------------------------------------------
# Közös bemenetek, származtatott értékek, adatforrások és a workspace-védelem
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "A projekt rövid azonosítója (pl. project-x)."
  type        = string
}

variable "env_name" {
  description = "A környezet rövid jele (sbx, dev, test). Egyeznie kell a Terraform workspace nevével."
  type        = string
}

variable "location" {
  description = "Azure-régió."
  type        = string
  default     = "swedencentral"
}

variable "owner" {
  description = "A környezet felelőse (owner tag)."
  type        = string
  default     = "platformengineer@vighsandor.hu"
}

variable "expires" {
  description = "A környezet lejárati dátuma (expires tag, ÉÉÉÉ-HH-NN)."
  type        = string

  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-\\d{2}$", var.expires)) && can(formatdate("YYYY", "${var.expires}T00:00:00Z"))
    error_message = "Az expires formátuma ÉÉÉÉ-HH-NN legyen, és létező dátum."
  }
}

# Az igénylés adatai. Korábban ezt egy külön igénylőlap (a pull request
# leírása) kérte be; most minden egy helyen, a környezet tfvars fájljában van,
# a Terraform ellenőrzi, és a state-ben is megmarad (terraform_data.request).
variable "request" {
  description = "Az igénylés: ki kérte, melyik csapat, miért, ki hagyta jóvá a költséget, és (ha eltér az alapértelmezettől) miért kell más méret."
  type = object({
    requester   = string               # az igénylő Entra ID UPN-je
    team        = string               # a csapat neve
    reason      = string               # mire kell a környezet
    approver    = string               # költséghely / jóváhagyó vezető
    size_reason = optional(string, "") # csak egyedi méretnél (node_vm_size, node_count)
  })

  validation {
    condition     = strcontains(var.request.requester, "@")
    error_message = "A request.requester az igénylő Entra ID UPN-je legyen (pl. nev@tenant.onmicrosoft.com)."
  }
  validation {
    condition     = length(trimspace(var.request.reason)) >= 10
    error_message = "A request.reason-ben írd le pár szóban, mire kell a környezet."
  }
  validation {
    condition     = length(trimspace(var.request.team)) > 0 && length(trimspace(var.request.approver)) > 0
    error_message = "A request.team és a request.approver kötelező."
  }
}

locals {
  resource_basename = "${var.project_name}-${var.env_name}"

  common_tags = {
    project     = var.project_name
    environment = var.env_name
    owner       = var.owner
    expires     = var.expires
    team        = var.request.team
    managed_by  = "terraform"
  }
}

data "azurerm_client_config" "current" {}

# Biztonsági zár: a dev változókkal nem lehet a sandbox workspace-ében
# futtatni (és fordítva), mert az a másik környezetet írná át.
resource "terraform_data" "workspace_guard" {
  input = var.env_name

  lifecycle {
    precondition {
      condition     = terraform.workspace == var.env_name
      error_message = "A workspace (${terraform.workspace}) nem egyezik a környezettel (${var.env_name}). Futtasd: terraform workspace select -or-create ${var.env_name}"
    }
  }
}

# Az igénylés rögzítése a state-ben: a plan-ben látszik, mit és miért kértek,
# és utólag is visszakereshető (terraform state show terraform_data.request).
resource "terraform_data" "request" {
  input = merge(var.request, {
    project = var.project_name
    env     = var.env_name
    expires = var.expires
  })

  lifecycle {
    precondition {
      condition     = (var.node_vm_size == "Standard_D2as_v5" && var.node_count == 1) || length(trimspace(var.request.size_reason)) > 0
      error_message = "Az alapértelmezettől eltérő mérethez (node_vm_size / node_count) indoklás kell: request.size_reason."
    }
  }
}
