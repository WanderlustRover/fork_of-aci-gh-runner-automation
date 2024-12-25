terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }

    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
  backend "azurerm" {
    resource_group_name  = "rg-terraform-core-eastus2"
    storage_account_name = "coreterraformeastus2"
    container_name       = "coretfstate"
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}
