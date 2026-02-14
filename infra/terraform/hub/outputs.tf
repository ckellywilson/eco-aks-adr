output "resource_group_id" {
  description = "Hub resource group ID"
  value       = azurerm_resource_group.hub.id
}

output "hub_vnet_id" {
  description = "Hub VNet resource ID"
  value       = module.hub_vnet.resource_id
}

output "hub_vnet_name" {
  description = "Hub VNet name"
  value       = module.hub_vnet.name
}

output "hub_vnet_address_space" {
  description = "Hub VNet address space"
  value       = var.hub_vnet_address_space
}

output "hub_subnets" {
  description = "Hub VNet subnets"
  value = {
    for name, subnet in module.hub_vnet.subnets : name => {
      id   = subnet.resource_id
      name = subnet.name
    }
  }
}

output "firewall_id" {
  description = "Azure Firewall resource ID"
  value       = try(module.firewall[0].firewall_id, null)
}

output "firewall_private_ip" {
  description = "Azure Firewall private IP address"
  value       = try(module.firewall[0].resource.ip_configurations[0].private_ip_address, try(module.firewall[0].firewall_private_ip, null))
}

output "firewall_public_ip" {
  description = "Azure Firewall public IP address"
  value       = try(azurerm_public_ip.firewall[0].ip_address, null)
}

output "firewall_policy_id" {
  description = "Firewall policy ID for spoke rule collection groups (priority >= 500)"
  value       = try(azurerm_firewall_policy.hub[0].id, null)
}

output "bastion_id" {
  description = "Azure Bastion resource ID"
  value       = try(module.bastion[0].bastion_id, null)
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace resource ID"
  value       = module.log_analytics.resource_id
}

output "log_analytics_workspace_name" {
  description = "Log Analytics workspace name"
  value       = module.log_analytics.resource.name
  sensitive   = true
}

output "private_dns_zone_ids" {
  description = "Map of private DNS zone names to IDs"
  value = {
    for zone_name, zone_module in module.private_dns_zones : zone_name => zone_module.resource_id
  }
}

output "dns_resolver_id" {
  description = "Private DNS Resolver resource ID"
  value       = try(azurerm_private_dns_resolver.hub[0].id, null)
}

output "dns_resolver_inbound_ip" {
  description = "DNS Resolver inbound endpoint IP address"
  value       = try(azurerm_private_dns_resolver_inbound_endpoint.hub[0].ip_configurations[0].private_ip_address, null)
}

output "dns_resolver_outbound_ip" {
  description = "DNS Resolver outbound endpoint IP address"
  value       = try(azurerm_private_dns_resolver_outbound_endpoint.hub[0].id, null)
}

output "hub_jumpbox_private_ip" {
  description = "Hub jump box VM private IP address"
  value       = try(azurerm_network_interface.hub_jumpbox[0].private_ip_address, null)
}

output "hub_jumpbox_id" {
  description = "Hub jump box VM resource ID"
  value       = try(azurerm_linux_virtual_machine.hub_jumpbox[0].id, null)
}

output "spoke_vnet_ids" {
  description = "Map of hub-managed spoke names to VNet resource IDs"
  value = {
    for k, v in module.spoke_vnet : k => v.resource_id
  }
}

output "spoke_resource_group_names" {
  description = "Map of hub-managed spoke names to resource group names"
  value = {
    for k, v in azurerm_resource_group.spoke : k => v.name
  }
}
