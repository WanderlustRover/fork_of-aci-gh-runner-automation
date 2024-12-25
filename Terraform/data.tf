data "azurerm_client_config" "current" {
}


# Resource group for core admin terraform created via my_subscription_setup.sh
data "azurerm_resource_group" "primary_rg" {
  name = "rg-terraform-core-eastus2"
}
