output "resource_group_name" {
  description = "CI/CD resource group name"
  value       = data.azurerm_resource_group.cicd.name
}

output "cicd_vnet_id" {
  description = "CI/CD VNet resource ID"
  value       = local.cicd_vnet_id
}

output "agent_pool_name" {
  description = "ADO agent pool name for self-hosted ACI agents"
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
