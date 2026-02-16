# Platform Key Vault — SSH public key for jump box VMs
# Created by setup-ado-pipeline.sh before any Terraform runs
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
