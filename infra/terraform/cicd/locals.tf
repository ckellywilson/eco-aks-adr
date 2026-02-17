locals {
  location_map = {
    eastus2 = "eus2"
    eastus  = "eus"
    westus2 = "wus2"
    westus  = "wus"
  }

  location_code = lookup(local.location_map, var.location, substr(var.location, 0, 4))

  # Hub integration flags — empty string = disabled (bootstrap mode)
  hub_integrated = var.hub_vnet_id != ""
  hub_dns_set    = var.hub_dns_resolver_ip != ""
  hub_acr_zone   = var.hub_acr_dns_zone_id != ""
  hub_log_ws     = var.hub_log_analytics_workspace_id != ""

  # Derive hub RG + VNet name from hub_vnet_id when available
  hub_rg_name   = local.hub_integrated ? split("/", var.hub_vnet_id)[4] : ""
  hub_vnet_name = local.hub_integrated ? split("/", var.hub_vnet_id)[8] : ""

  # State SA — derive name from resource ID
  state_sa_enabled = var.state_storage_account_id != ""

  common_tags = merge(
    var.tags,
    {
      CreatedBy   = "Terraform"
      Environment = var.environment
    }
  )

  # CI/CD VNet subnet layout (10.2.0.0/24)
  # container_app:      10.2.0.0/27  — Container App Environment (delegation: Microsoft.App/environments)
  # aci_agents_acr:     10.2.0.32/29 — ACR private endpoint for agent images
  # private_endpoints:  10.2.0.48/28 — State SA + Platform KV private endpoints
  subnet_config = {
    container_app = {
      name             = "container-app"
      address_prefixes = [var.container_app_subnet_cidr]
      delegation = [
        {
          name = "Microsoft.App.environments"
          service_delegation = {
            name    = "Microsoft.App/environments"
            actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
          }
        }
      ]
    }
    aci_agents_acr = {
      name             = "aci-agents-acr"
      address_prefixes = [var.aci_agents_acr_subnet_cidr]
    }
  }
}
