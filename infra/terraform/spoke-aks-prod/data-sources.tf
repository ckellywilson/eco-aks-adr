# Read hub outputs
# This allows the spoke to consume hub resources
# Note: Hub outputs file is generated after hub deployment
locals {
  hub_outputs = try(jsondecode(file("../hub-eastus/hub-eastus-outputs.json")), {
    hub_vnet_id                = null
    firewall_private_ip        = null
    log_analytics_workspace_id = null
    private_dns_zone_ids       = {}
  })
}

# Reference hub resources via data sources if file doesn't exist yet
data "azurerm_virtual_network" "hub" {
  count               = local.hub_outputs.hub_vnet_id == null ? 1 : 0
  name                = "vnet-hub-${var.environment}-${local.location_code}"
  resource_group_name = var.hub_resource_group_name
}

data "azurerm_log_analytics_workspace" "hub" {
  count               = local.hub_outputs.log_analytics_workspace_id == null ? 1 : 0
  name                = "law-hub-${var.environment}-${local.location_code}"
  resource_group_name = var.hub_resource_group_name
}
