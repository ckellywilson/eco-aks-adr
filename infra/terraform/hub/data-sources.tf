# Platform Key Vault — SSH public key for jump box VMs
# Created by setup-ado-pipeline.sh before any Terraform runs
locals {
  platform_kv_id_parts = split("/", var.platform_key_vault_id)
  platform_kv_name     = element(local.platform_kv_id_parts, length(local.platform_kv_id_parts) - 1)
  platform_kv_rg       = element(local.platform_kv_id_parts, length(local.platform_kv_id_parts) - 5)
}

data "azurerm_key_vault" "platform" {
  name                = local.platform_kv_name
  resource_group_name = local.platform_kv_rg
}

data "azurerm_key_vault_secret" "ssh_public_key" {
  name         = "ssh-public-key"
  key_vault_id = data.azurerm_key_vault.platform.id
}
