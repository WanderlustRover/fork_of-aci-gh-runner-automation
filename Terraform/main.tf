module "aci" {
  source = "./modules/aci"

  gh_pat            = var.gh_pat
  gh_repo_url       = var.gh_repo_url
  resourceGroupName = data.azurerm_resource_group.primary_rg.name
  vnetName          = azurerm_virtual_network.vnet.name
}

