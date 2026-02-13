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

# Read Azure Firewall to get private IP address
# (workaround for module output issue)
data "azurerm_firewall" "hub" {
  name                = "afw-hub-prod-eus2"
  resource_group_name = var.hub_resource_group_name
}

locals {
  hub_outputs         = data.terraform_remote_state.hub.outputs
  firewall_private_ip = data.azurerm_firewall.hub.ip_configuration[0].private_ip_address
}
