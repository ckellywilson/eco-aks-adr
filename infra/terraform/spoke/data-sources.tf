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
    resource_group_name  = "rg-tfstate-eus2-prod"
    storage_account_name = "sttfstateeus2d2c496b3"
    container_name       = "tfstate-hub"
    key                  = "terraform.tfstate"
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

# Platform Key Vault — SSH public key for jump box VMs
locals {
  # Parse KV resource ID with regex for robustness (case-insensitive on fixed segments)
  # Expected: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.KeyVault/vaults/{name}
  platform_kv_id_parts = regex("(?i)/subscriptions/[^/]+/resourceGroups/([^/]+)/providers/Microsoft\\.KeyVault/vaults/([^/]+)$", var.platform_key_vault_id)
  platform_kv_rg       = local.platform_kv_id_parts[0]
  platform_kv_name     = local.platform_kv_id_parts[1]
}

data "azurerm_key_vault" "platform" {
  name                = local.platform_kv_name
  resource_group_name = local.platform_kv_rg
}

data "azurerm_key_vault_secret" "ssh_public_key" {
  name         = "ssh-public-key"
  key_vault_id = data.azurerm_key_vault.platform.id
}
