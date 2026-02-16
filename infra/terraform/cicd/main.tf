# =============================================================================
# CI/CD Landing Zone — Self-Hosted ACI-Based ADO Pipeline Agents
# =============================================================================
# Deploys ACI containers in a dedicated CI/CD VNet that register as ADO agents.
# One pool serves ALL peered spokes (no per-spoke agent pools needed).
#
# Uses AVM pattern module: Azure/avm-ptn-cicd-agents-and-runners/azurerm
# Auth: UAMI (no PAT tokens), private networking, Microsoft-maintained images.
#
# The CI/CD VNet is hub-managed — the hub creates the RG + VNet + peering.
# This module deploys subnets and agents INTO the hub-created infrastructure.
# =============================================================================

# --- Subnets ---
# Add application-specific subnets to the hub-created CI/CD VNet
module "cicd_subnets" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "~> 0.8"

  name                = local.cicd_vnet_name
  resource_group_name = local.cicd_rg_name
  location            = var.location
  address_space       = data.azurerm_virtual_network.cicd.address_space

  subnets = local.subnet_config

  enable_telemetry = true
  tags             = local.common_tags
}

# --- Managed Identity ---
# UAMI for ACI agents — authenticates with ADO and accesses platform KV
resource "azurerm_user_assigned_identity" "cicd_agents" {
  name                = "uami-cicd-agents-${var.environment}-${local.location_code}"
  resource_group_name = local.cicd_rg_name
  location            = var.location

  tags = local.common_tags
}

# Grant ACI agents read access to platform KV (SSH keys, platform secrets)
resource "azurerm_role_assignment" "cicd_agents_kv_reader" {
  scope                = var.platform_key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.cicd_agents.principal_id
}

# --- AVM CI/CD Agents Module ---
module "cicd_agents" {
  source  = "Azure/avm-ptn-cicd-agents-and-runners/azurerm"
  version = "~> 0.5"

  postfix = "cicd-${var.environment}"

  # Use hub-created resource group
  resource_group_creation_enabled = false
  resource_group_name             = local.cicd_rg_name
  location                        = var.location

  # Compute type: ACI with existing VNet injection
  compute_types                       = ["azure_container_instance"]
  virtual_network_creation_enabled    = false
  virtual_network_id                  = local.cicd_vnet_id
  container_instance_subnet_id        = module.cicd_subnets.subnets["aci_agents"].resource_id
  container_instance_count            = var.aci_agent_count
  use_default_container_image         = true
  use_private_networking              = true
  container_instance_container_cpu    = 2
  container_instance_container_memory = 4

  # ACR private endpoint — use hub's existing DNS zone and CI/CD subnet
  container_registry_private_dns_zone_creation_enabled = false
  container_registry_dns_zone_id                       = local.hub_outputs.private_dns_zone_ids["privatelink.azurecr.io"]
  container_registry_private_endpoint_subnet_id        = module.cicd_subnets.subnets["aci_agents_acr"].resource_id

  # ADO configuration
  version_control_system_type         = "azuredevops"
  version_control_system_organization = var.ado_organization_url
  version_control_system_pool_name    = var.ado_agent_pool_name

  # Auth: UAMI — no PAT tokens
  version_control_system_authentication_method    = "uami"
  user_assigned_managed_identity_creation_enabled = false
  user_assigned_managed_identity_id               = azurerm_user_assigned_identity.cicd_agents.id
  user_assigned_managed_identity_client_id        = azurerm_user_assigned_identity.cicd_agents.client_id
  user_assigned_managed_identity_principal_id     = azurerm_user_assigned_identity.cicd_agents.principal_id

  # Use hub's centralized Log Analytics workspace
  log_analytics_workspace_creation_enabled = false
  log_analytics_workspace_id               = local.hub_outputs.log_analytics_workspace_id

  # NAT Gateway — required for ACI outbound connectivity.
  # ACI delegated subnets do not support UDRs, so outbound via Azure Firewall is not viable;
  # keep this enabled to ensure ACI agents can register with ADO.
  nat_gateway_creation_enabled = true

  enable_telemetry = true
  tags             = local.common_tags

  depends_on = [
    azurerm_role_assignment.cicd_agents_kv_reader,
    module.cicd_subnets,
  ]
}
