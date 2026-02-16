locals {
  location_map = {
    eastus2 = "eus2"
    eastus  = "eus"
    westus2 = "wus2"
    westus  = "wus"
  }

  location_code = lookup(local.location_map, var.location, substr(var.location, 0, 4))

  hub_outputs    = data.terraform_remote_state.hub.outputs
  cicd_rg_name   = data.azurerm_resource_group.cicd.name
  cicd_vnet_id   = local.hub_outputs.spoke_vnet_ids[var.spoke_key]
  cicd_vnet_name = data.azurerm_virtual_network.cicd.name

  common_tags = merge(
    var.tags,
    {
      CreatedBy   = "Terraform"
      Environment = var.environment
    }
  )

  # CI/CD VNet subnet layout (10.2.0.0/24)
  # aci_agents:     10.2.0.0/27  — ACI containers (delegation: Microsoft.ContainerInstance)
  # aci_agents_acr: 10.2.0.32/29 — ACR private endpoint for agent images
  subnet_config = {
    aci_agents = {
      name             = "aci-agents"
      address_prefixes = [var.aci_agents_subnet_cidr]
      delegation = [
        {
          name = "Microsoft.ContainerInstance.containerGroups"
          service_delegation = {
            name    = "Microsoft.ContainerInstance/containerGroups"
            actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
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
