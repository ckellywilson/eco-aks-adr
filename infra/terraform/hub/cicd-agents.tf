# =============================================================================
# Self-Hosted ACI-Based ADO Pipeline Agents
# =============================================================================
# Deploys ACI containers in the hub VNet that register as ADO pipeline agents.
# One pool in the hub serves ALL peered spokes (no per-spoke agent pools needed).
#
# Uses AVM pattern module: Azure/avm-ptn-cicd-agents-and-runners/azurerm
# Auth: UAMI (no PAT tokens), private networking, Microsoft-maintained images.
#
# Conditional on var.deploy_cicd_agents — skip for initial bootstrap deploy.
# =============================================================================

# UAMI for ACI agents — used to authenticate with ADO and access platform KV
resource "azurerm_user_assigned_identity" "cicd_agents" {
  count               = var.deploy_cicd_agents ? 1 : 0
  name                = "uami-cicd-agents-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location

  tags = local.common_tags
}

# Grant ACI agents read access to platform KV (SSH keys, platform secrets)
resource "azurerm_role_assignment" "cicd_agents_kv_reader" {
  count                = var.deploy_cicd_agents ? 1 : 0
  scope                = var.platform_key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.cicd_agents[0].principal_id
}

# AVM CI/CD Agents module — deploys ACI containers as ADO agents
module "cicd_agents" {
  count   = var.deploy_cicd_agents ? 1 : 0
  source  = "Azure/avm-ptn-cicd-agents-and-runners/azurerm"
  version = "~> 0.5"

  # Use existing resource group
  resource_group_creation_enabled = false
  resource_group_name             = azurerm_resource_group.hub.name
  location                        = var.location

  # Compute type: ACI with existing VNet injection
  compute_types                       = ["azure_container_instance"]
  virtual_network_creation_enabled    = false
  virtual_network_id                  = module.hub_vnet.resource_id
  container_instance_subnet_id        = module.hub_vnet.subnets["aci_agents"].resource_id
  container_instance_count            = var.aci_agent_count
  use_default_container_image         = true
  use_private_networking              = true
  container_instance_container_cpu    = 2
  container_instance_container_memory = 4

  # ADO configuration
  version_control_system_type         = "azuredevops"
  version_control_system_organization = var.ado_organization_url
  version_control_system_pool_name    = var.ado_agent_pool_name

  # Auth: UAMI — no PAT tokens
  version_control_system_authentication_method      = "uami"
  version_control_system_managed_identity_client_id = azurerm_user_assigned_identity.cicd_agents[0].client_id
  managed_identities = {
    user_assigned_resource_ids = [azurerm_user_assigned_identity.cicd_agents[0].id]
  }

  # Use existing Log Analytics workspace
  log_analytics_workspace_creation_enabled = false
  log_analytics_workspace_id               = module.log_analytics.resource_id

  # ACR private endpoint for agent images — use hub's DNS zone
  container_registry_private_dns_zone_creation_enabled = false
  container_registry_dns_zone_id                       = module.private_dns_zones["privatelink.azurecr.io"].resource_id

  enable_telemetry = true
  tags             = local.common_tags

  depends_on = [
    azurerm_role_assignment.cicd_agents_kv_reader,
  ]
}
