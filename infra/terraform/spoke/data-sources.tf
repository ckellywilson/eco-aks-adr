# Read hub outputs from Terraform remote state
# This ensures the spoke always references the current hub infrastructure
# by reading directly from the hub's state file in the backend
# 
# Authentication:
# - Local: Uses Azure AD tokens from `az login`; set ARM_USE_AZUREAD=true
# - ADO: Set ARM_USE_OIDC=true env var for Workload Identity OIDC
data "terraform_remote_state" "hub" {
  backend = "azurerm"

  config = {
    resource_group_name  = "rg-terraform-state-dev"
    storage_account_name = "sttfstatedevd3120d7a"
    container_name       = "terraform-state-prod"
    key                  = "hub/terraform.tfstate"
    use_azuread_auth     = true
  }
}

# Reference the hub-created spoke resource group (hub_managed = true)
data "azurerm_resource_group" "spoke" {
  name = local.hub_outputs.spoke_resource_group_names[var.spoke_key]
}

# Reference the hub-created spoke VNet (hub_managed = true)
data "azurerm_virtual_network" "spoke" {
  name                = try(local.hub_outputs.spoke_vnet_names[var.spoke_key], "${var.spoke_key}-vnet")
  resource_group_name = data.azurerm_resource_group.spoke.name
}

locals {
  hub_outputs         = data.terraform_remote_state.hub.outputs
  spoke_rg_name       = data.azurerm_resource_group.spoke.name
  spoke_vnet_id       = local.hub_outputs.spoke_vnet_ids[var.spoke_key]
  spoke_vnet_name     = data.azurerm_virtual_network.spoke.name
  spoke_vnet_cidr     = data.azurerm_virtual_network.spoke.address_space[0]
  firewall_private_ip = try(local.hub_outputs.firewall_private_ip, null)
}
