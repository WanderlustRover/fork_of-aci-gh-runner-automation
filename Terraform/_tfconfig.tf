terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
    }
  }
  backend "azurerm" {
      resource_group_name  = "tfstate"
      storage_account_name = "tfstate31858"
      container_name       = "tfstate"
      key                  = "terraform.tfstate"
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}
