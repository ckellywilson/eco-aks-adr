# =============================================================================
# CI/CD Landing Zone — Self-Hosted ACI-Based ADO Pipeline Agents
# =============================================================================
# Deploys ACI containers in a dedicated CI/CD VNet that register as ADO agents.
# One pool serves ALL peered spokes (no per-spoke agent pools needed).
#
# Uses AVM pattern module: Azure/avm-ptn-cicd-agents-and-runners/azurerm
# Auth: UAMI (no PAT tokens), private networking, Microsoft-maintained images.
#
# This module is SELF-CONTAINED — it creates its own RG, VNet, and peering.
# It reads hub outputs (DNS resolver IP, DNS zones, Log Analytics) via remote state.
# =============================================================================

# --- Resource Group ---
resource "azurerm_resource_group" "cicd" {
  name     = var.cicd_resource_group_name
  location = var.location
  tags     = local.common_tags
}

# --- VNet ---
# Custom DNS points to hub DNS resolver for private endpoint resolution
resource "azurerm_virtual_network" "cicd" {
  name                = var.cicd_vnet_name
  resource_group_name = azurerm_resource_group.cicd.name
  location            = azurerm_resource_group.cicd.location
  address_space       = var.cicd_vnet_address_space
  dns_servers         = [local.hub_outputs.dns_resolver_inbound_ip]
  tags                = local.common_tags
}

# --- VNet Peering (bidirectional) ---
resource "azurerm_virtual_network_peering" "cicd_to_hub" {
  name                      = "peer-cicd-to-hub"
  resource_group_name       = azurerm_resource_group.cicd.name
  virtual_network_name      = azurerm_virtual_network.cicd.name
  remote_virtual_network_id = local.hub_outputs.hub_vnet_id
  allow_forwarded_traffic   = true
}

resource "azurerm_virtual_network_peering" "hub_to_cicd" {
  name                      = "peer-hub-to-cicd"
  resource_group_name       = local.hub_rg_name
  virtual_network_name      = local.hub_vnet_name
  remote_virtual_network_id = azurerm_virtual_network.cicd.id
  allow_forwarded_traffic   = true
}

# --- Subnets ---
resource "azurerm_subnet" "aci_agents" {
  name                 = "aci-agents"
  resource_group_name  = azurerm_resource_group.cicd.name
  virtual_network_name = azurerm_virtual_network.cicd.name
  address_prefixes     = [var.aci_agents_subnet_cidr]

  delegation {
    name = "Microsoft.ContainerInstance.containerGroups"
    service_delegation {
      name    = "Microsoft.ContainerInstance/containerGroups"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "aci_agents_acr" {
  name                 = "aci-agents-acr"
  resource_group_name  = azurerm_resource_group.cicd.name
  virtual_network_name = azurerm_virtual_network.cicd.name
  address_prefixes     = [var.aci_agents_acr_subnet_cidr]
}

# --- Random suffix for globally unique ACR name ---
resource "random_string" "acr_suffix" {
  length  = 6
  special = false
  upper   = false
}

# --- Managed Identity ---
# UAMI for ACI agents — authenticates with ADO and accesses platform KV
resource "azurerm_user_assigned_identity" "cicd_agents" {
  name                = "uami-cicd-agents-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.cicd.name
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

  # Use self-created resource group
  resource_group_creation_enabled = false
  resource_group_name             = azurerm_resource_group.cicd.name
  location                        = var.location

  # Compute type: ACI with existing VNet injection
  compute_types                       = ["azure_container_instance"]
  virtual_network_creation_enabled    = false
  virtual_network_id                  = azurerm_virtual_network.cicd.id
  container_instance_subnet_id        = azurerm_subnet.aci_agents.id
  container_instance_count            = var.aci_agent_count
  use_default_container_image         = true
  use_private_networking              = true
  container_instance_container_cpu    = 2
  container_instance_container_memory = 4

  # ACR name must be globally unique (alphanumeric only)
  container_registry_name = "acrcicd${var.environment}${local.location_code}${random_string.acr_suffix.result}"

  # ACR private endpoint — use hub's existing DNS zone and CI/CD subnet
  container_registry_private_dns_zone_creation_enabled = false
  container_registry_dns_zone_id                       = local.hub_outputs.private_dns_zone_ids["privatelink.azurecr.io"]
  container_registry_private_endpoint_subnet_id        = azurerm_subnet.aci_agents_acr.id

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
    azurerm_subnet.aci_agents,
    azurerm_subnet.aci_agents_acr,
  ]
}
