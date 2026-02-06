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
      CreatedBy = "Terraform"
      CreatedAt = timestamp()
    }
  )

  subnet_config = {
    AzureFirewallSubnet = {
      name             = "AzureFirewallSubnet"
      address_prefixes = ["10.0.1.0/26"]
    }
    AzureBastionSubnet = {
      name             = "AzureBastionSubnet"
      address_prefixes = ["10.0.2.0/27"]
    }
    GatewaySubnet = {
      name             = "GatewaySubnet"
      address_prefixes = ["10.0.3.0/27"]
    }
    management = {
      name             = "management"
      address_prefixes = ["10.0.4.0/24"]
    }
    AppGatewaySubnet = {
      name             = "AppGatewaySubnet"
      address_prefixes = ["10.0.5.0/26"]
    }
    dns_resolver_inbound = {
      name             = "dns-resolver-inbound"
      address_prefixes = ["10.0.6.0/28"]
      delegation = {
        name = "Microsoft.Network.dnsResolvers"
        service_delegation = {
          name = "Microsoft.Network/dnsResolvers"
        }
      }
    }
    dns_resolver_outbound = {
      name             = "dns-resolver-outbound"
      address_prefixes = ["10.0.7.0/28"]
      delegation = {
        name = "Microsoft.Network.dnsResolvers"
        service_delegation = {
          name = "Microsoft.Network/dnsResolvers"
        }
      }
    }
  }
}
