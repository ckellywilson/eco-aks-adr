# Read hub outputs from Terraform remote state
# CI/CD landing zone consumes hub infrastructure (DNS zones, Log Analytics, VNet)
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

# Reference the hub-created CI/CD resource group (hub_managed = true)
data "azurerm_resource_group" "cicd" {
  name = local.hub_outputs.spoke_resource_group_names[var.spoke_key]
}

# Reference the hub-created CI/CD VNet (hub_managed = true)
data "azurerm_virtual_network" "cicd" {
  name                = try(local.hub_outputs.spoke_vnet_names[var.spoke_key], "${var.spoke_key}-vnet")
  resource_group_name = data.azurerm_resource_group.cicd.name
}
