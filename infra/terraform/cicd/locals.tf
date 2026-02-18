locals {
  location_map = {
    eastus2 = "eus2"
    eastus  = "eus"
    westus2 = "wus2"
    westus  = "wus"
  }

  location_code = lookup(local.location_map, var.location, substr(var.location, 0, 4))

  # Derive hub RG + VNet name from hub_vnet_id
  hub_rg_name   = split("/", var.hub_vnet_id)[4]
  hub_vnet_name = split("/", var.hub_vnet_id)[8]

  # State SA — derive enablement from resource ID
  state_sa_enabled = var.state_storage_account_id != ""

  common_tags = merge(
    var.tags,
    {
      CreatedBy   = "Terraform"
      Environment = var.environment
    }
  )
}
