resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  address_space       = ["10.240.10.0/24"]
  resource_group_name = data.azurerm_resource_group.primary_rg.name
  location            = data.azurerm_resource_group.primary_rg.location
}
