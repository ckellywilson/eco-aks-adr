output "resource_group_name" {
  description = "CI/CD resource group name"
  value       = azurerm_resource_group.cicd.name
}

output "cicd_vnet_id" {
  description = "CI/CD VNet resource ID"
  value       = azurerm_virtual_network.cicd.id
}

output "agent_pool_name" {
  description = "ADO agent pool name for self-hosted Container App Job agents"
  value       = var.ado_agent_pool_name
}

output "agent_uami_id" {
  description = "CI/CD agent UAMI resource ID"
  value       = azurerm_user_assigned_identity.cicd_agents.id
}

output "agent_uami_client_id" {
  description = "CI/CD agent UAMI client ID (for ADO UAMI registration)"
  value       = azurerm_user_assigned_identity.cicd_agents.client_id
}

output "agent_uami_principal_id" {
  description = "CI/CD agent UAMI principal ID"
  value       = azurerm_user_assigned_identity.cicd_agents.principal_id
}

output "state_sa_pe_ip" {
  description = "State SA private endpoint IP address"
  value       = local.state_sa_enabled ? azurerm_private_endpoint.state_sa[0].private_service_connection[0].private_ip_address : null
}

output "platform_kv_pe_ip" {
  description = "Platform KV private endpoint IP address"
  value       = var.platform_key_vault_id != "" ? azurerm_private_endpoint.platform_kv[0].private_service_connection[0].private_ip_address : null
}
