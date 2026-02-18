# Platform Key Vault — SSH public key for jump box VMs
# Only read when jump box is deployed (KV has private access only;
# hub runs on MS-hosted agents which cannot reach it)
locals {
  platform_kv_id_parts = var.deploy_jumpbox ? regex("(?i)/subscriptions/[^/]+/resourceGroups/([^/]+)/providers/Microsoft\\.KeyVault/vaults/([^/]+)$", var.platform_key_vault_id) : ["", ""]
  platform_kv_rg       = local.platform_kv_id_parts[0]
  platform_kv_name     = local.platform_kv_id_parts[1]
}

data "azurerm_key_vault" "platform" {
  count               = var.deploy_jumpbox ? 1 : 0
  name                = local.platform_kv_name
  resource_group_name = local.platform_kv_rg
}

data "azurerm_key_vault_secret" "ssh_public_key" {
  count        = var.deploy_jumpbox ? 1 : 0
  name         = "ssh-public-key"
  key_vault_id = data.azurerm_key_vault.platform[0].id
}
