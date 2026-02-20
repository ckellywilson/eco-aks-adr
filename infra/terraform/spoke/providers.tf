provider "azurerm" {
  subscription_id = var.subscription_id

  # Authentication priority (checked in order):
  # 1. Environment variables (ARM_USE_OIDC, ARM_USE_MSI, etc.)
  # 2. Azure CLI credentials (from `az login`)
  # 3. Managed Service Identity (in Azure VMs)
  #
  # For ADO: Set ARM_USE_OIDC=true for Workload Identity OIDC
  # For Local: Use `az login` for interactive Azure AD tokens

  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }

    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}
