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
    key                  = "hub-eastus/terraform.tfstate"
  }
}

locals {
  hub_outputs = data.terraform_remote_state.hub.outputs
}
