# -----------------------------------------------------------------------------
# Terraform, backend és providerek
# A state az Azure Storage-ban (course-baseline / platencbvighsandor / tfstate)
# él; a repóba a létrehozó script egy pillanatképet ment: state/<név>.tfstate
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.4"

  backend "azurerm" {
    use_cli              = true
    use_azuread_auth     = true
    resource_group_name  = "course-baseline"
    storage_account_name = "platencbvighsandor"
    container_name       = "tfstate"
    key                  = "project-x-sbx.tfstate"
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "5.3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "3.9.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449"
  tenant_id       = "c9b482b1-d17b-430e-bbe6-5d64ba800aa1"
}

provider "azuread" {
  tenant_id = "c9b482b1-d17b-430e-bbe6-5d64ba800aa1"
}
