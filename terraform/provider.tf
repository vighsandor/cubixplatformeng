# -----------------------------------------------------------------------------
# Terraform, backend és providerek
#
# Egy kód, több környezet: a környezetet a Terraform workspace választja ki
# (sbx, dev, ...), a bemeneteit pedig az environments/<env>.tfvars fájl adja.
# A state az Azure Storage-ban workspace-enként külön blobban él:
#   project-x.tfstateenv:<workspace>
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5"

  backend "azurerm" {
    use_cli              = true
    use_azuread_auth     = true
    resource_group_name  = "course-baseline"
    storage_account_name = "platencbvighsandor"
    container_name       = "tfstate"
    key                  = "project-x.tfstate"
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
    helm = {
      source  = "hashicorp/helm"
      version = "3.2.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.14.2"
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

# A Helm a környezet saját AKS-ét éri el. Helyi fiókok nincsenek, ezért a
# tokent a kubelogin kéri az Azure CLI bejelentkezéséből – helyben a saját
# felhasználómmal, a pipeline-ban a github-repos managed identityvel.
provider "helm" {
  kubernetes = {
    host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "kubelogin"
      args = [
        "get-token",
        "--login", "azurecli",
        "--server-id", "6dae42f8-4368-4678-94ff-3960e28e3630", # az AKS Entra ID-alkalmazása (Azure public cloud)
      ]
    }
  }
}
