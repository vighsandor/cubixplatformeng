# -----------------------------------------------------------------------------
# Közös bemenetek, származtatott értékek és adatforrások
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "A projekt rövid azonosítója (pl. project-x)."
  type        = string
}

variable "env_name" {
  description = "A környezet rövid jele (sbx, dev, test)."
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

# Annak az identitásnak az adatai, amelynek a nevében a Terraform fut
# (helyi futtatásnál: a bejelentkezett felhasználó).
data "azurerm_client_config" "current" {}
