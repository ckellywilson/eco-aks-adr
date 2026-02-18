locals {
  location_map = {
    eastus2 = "eus2"
    eastus  = "eus"
    westus2 = "wus2"
    westus  = "wus"
  }

  location_code = lookup(local.location_map, var.location, substr(var.location, 0, 4))

  # Hub integration flags — empty values = bootstrap mode (no hub)
  hub_integrated     = var.hub_vnet_id != ""
  use_hub_acr_zone   = var.hub_acr_dns_zone_id != ""
  use_hub_blob_zone  = var.hub_blob_dns_zone_id != ""
  use_hub_vault_zone = var.hub_vault_dns_zone_id != ""

  # Derive hub RG + VNet name from hub_vnet_id (only when hub is integrated)
  hub_rg_name   = local.hub_integrated ? split("/", var.hub_vnet_id)[4] : ""
  hub_vnet_name = local.hub_integrated ? split("/", var.hub_vnet_id)[8] : ""

  # State SA — derive enablement from resource ID
  state_sa_enabled           = var.state_storage_account_id != ""
  hub_spoke_state_sa_enabled = var.hub_spoke_state_storage_account_id != ""

  # Resolved DNS zone IDs — use hub zones when available, CI/CD-owned zones otherwise
  blob_dns_zone_id  = local.use_hub_blob_zone ? var.hub_blob_dns_zone_id : azurerm_private_dns_zone.blob[0].id
  vault_dns_zone_id = local.use_hub_vault_zone ? var.hub_vault_dns_zone_id : azurerm_private_dns_zone.vault[0].id
  acr_dns_zone_id   = local.use_hub_acr_zone ? var.hub_acr_dns_zone_id : azurerm_private_dns_zone.acr[0].id

  common_tags = merge(
    var.tags,
    {
      CreatedBy   = "Terraform"
      Environment = var.environment
    }
  )
}
