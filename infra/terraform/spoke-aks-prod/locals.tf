locals {
  location_map = {
    eastus2 = "eus2"
    eastus  = "eus"
    westus2 = "wus2"
    westus  = "wus"
  }

  location_code = lookup(local.location_map, var.location, substr(var.location, 0, 4))

  common_tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
    }
  )

  subnet_config = {
    aks_nodes = {
      name             = "aks-nodes"
      address_prefixes = ["10.1.0.0/22"]
      route_table = {
        id = azurerm_route_table.spoke.id
      }
      network_security_group = {
        id = azurerm_network_security_group.aks_nodes.id
      }
    }
    aks_system = {
      name             = "aks-system"
      address_prefixes = ["10.1.4.0/24"]
    }
    management = {
      name             = "management"
      address_prefixes = ["10.1.5.0/24"]
    }
  }
}
