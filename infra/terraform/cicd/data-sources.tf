# Read hub outputs from Terraform remote state
# CI/CD landing zone consumes hub infrastructure (DNS zones, Log Analytics, hub VNet for peering)
#
# Authentication:
# - Local: Uses Azure AD tokens from `az login`; set ARM_USE_AZUREAD=true
# - ADO: Set ARM_USE_OIDC=true env var for Workload Identity OIDC
data "terraform_remote_state" "hub" {
  backend = "azurerm"

  config = {
    resource_group_name  = "rg-terraform-state-dev"
    storage_account_name = "sttfstatedevd3120d7a"
    container_name       = "tfstate-hub"
    key                  = "terraform.tfstate"
    use_azuread_auth     = true
  }
}
