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
}

locals {
  resource_basename = "${var.project_name}-${var.env_name}"

  common_tags = {
    project     = var.project_name
    environment = var.env_name
    owner       = var.owner
    expires     = var.expires
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
