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
      CreatedBy   = "Terraform"
      Environment = var.environment
    }
  )

  # Allowed source addresses for firewall rules (hub + all spokes)
  allowed_source_addresses = concat(
    var.hub_vnet_address_space,
    flatten([for k, v in var.spoke_vnets : v.address_space]),
    var.spoke_vnet_address_spaces
  )

  # Split spokes by provisioning mode
  hub_managed_spokes = { for k, v in var.spoke_vnets : k => v if v.hub_managed }
  delegated_spokes   = { for k, v in var.spoke_vnets : k => v if !v.hub_managed }

  subnet_config = {
    AzureFirewallSubnet = {
      name             = "AzureFirewallSubnet"
      address_prefixes = ["10.0.1.0/26"]
    }
    AzureBastionSubnet = {
      name             = "AzureBastionSubnet"
      address_prefixes = ["10.0.2.0/27"]
    }
    # Reserved for future VPN/ExpressRoute gateway deployment; do not reuse this address space.
    GatewaySubnet = {
      name             = "GatewaySubnet"
      address_prefixes = ["10.0.3.0/27"]
      # Reserved for future VPN/ExpressRoute gateway deployment; do not reuse this address space.
    }
    management = {
      name             = "management"
      address_prefixes = ["10.0.4.0/24"]
    }
    dns_resolver_inbound = {
      name             = "dns-resolver-inbound"
      address_prefixes = ["10.0.6.0/28"]
      delegation = [
        {
          name = "Microsoft.Network/dnsResolvers"
          service_delegation = {
            name    = "Microsoft.Network/dnsResolvers"
            actions = []
          }
        }
      ]
    }
    dns_resolver_outbound = {
      name             = "dns-resolver-outbound"
      address_prefixes = ["10.0.7.0/28"]
      delegation = [
        {
          name = "Microsoft.Network/dnsResolvers"
          service_delegation = {
            name    = "Microsoft.Network/dnsResolvers"
            actions = []
          }
        }
      ]
    }
  }

  # ACI agent subnets — only included when deploy_cicd_agents is true
  aci_subnet_config = var.deploy_cicd_agents ? {
    aci_agents = {
      name             = "aci-agents"
      address_prefixes = ["10.0.8.0/27"]
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
      address_prefixes = ["10.0.9.0/29"]
    }
  } : {}

  # Merge base subnets with conditional ACI subnets
  all_subnet_config = merge(local.subnet_config, local.aci_subnet_config)
}
