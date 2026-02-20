# =============================================================================
# CI/CD Landing Zone — Self-Hosted Container App Job ADO Pipeline Agents
# =============================================================================
# Deploys Container App Jobs in a dedicated CI/CD VNet that register as ADO agents.
# One pool serves ALL peered spokes (no per-spoke agent pools needed).
#
# Uses AVM pattern module: Azure/avm-ptn-cicd-agents-and-runners/azurerm
# Auth: UAMI (no PAT tokens), private networking, KEDA auto-scaling (0 to N).
#
# This module is SELF-CONTAINED — it creates its own RG, VNet, and peering.
# Hub is OPTIONAL — bootstrap deploys without hub, Day 2 adds hub integration.
# Deployment order: CI/CD first (bootstrap) → Hub → CI/CD Day 2 → Spoke.
# =============================================================================

# --- Resource Group ---
resource "azurerm_resource_group" "cicd" {
  name     = var.cicd_resource_group_name
  location = var.location
  tags     = local.common_tags
}

# --- VNet ---
# Bootstrap: no custom DNS (Azure default resolves CI/CD-owned private DNS zones)
# Day 2: custom DNS points to hub DNS resolver for centralized resolution
resource "azurerm_virtual_network" "cicd" {
  name                = var.cicd_vnet_name
  resource_group_name = azurerm_resource_group.cicd.name
  location            = azurerm_resource_group.cicd.location
  address_space       = var.cicd_vnet_address_space
  dns_servers         = var.hub_dns_resolver_ip != "" ? [var.hub_dns_resolver_ip] : []
  tags                = local.common_tags
}

# --- VNet Peering (conditional — only when hub exists) ---
resource "azurerm_virtual_network_peering" "cicd_to_hub" {
  count                     = local.hub_integrated ? 1 : 0
  name                      = "peer-cicd-to-hub"
  resource_group_name       = azurerm_resource_group.cicd.name
  virtual_network_name      = azurerm_virtual_network.cicd.name
  remote_virtual_network_id = var.hub_vnet_id
  allow_forwarded_traffic   = true
}

resource "azurerm_virtual_network_peering" "hub_to_cicd" {
  count                     = local.hub_integrated ? 1 : 0
  name                      = "peer-hub-to-cicd"
  resource_group_name       = local.hub_rg_name
  virtual_network_name      = local.hub_vnet_name
  remote_virtual_network_id = azurerm_virtual_network.cicd.id
  allow_forwarded_traffic   = true
}

# --- Spoke VNet Peering (for private AKS access) ---
# VNet peering is not transitive — CI/CD ↔ Hub peering does NOT give CI/CD
# network access to spokes. Each spoke with a private AKS cluster needs a
# direct peering so agents can reach the AKS API server.
resource "azurerm_virtual_network_peering" "cicd_to_spoke" {
  for_each                  = var.spoke_vnet_ids
  name                      = "peer-cicd-to-${each.key}"
  resource_group_name       = azurerm_resource_group.cicd.name
  virtual_network_name      = azurerm_virtual_network.cicd.name
  remote_virtual_network_id = each.value
  allow_forwarded_traffic   = true
}

# NOTE: CI/CD service principal needs Network Contributor on each spoke RG
# to create this peering direction (same pattern as hub_to_cicd peering).
resource "azurerm_virtual_network_peering" "spoke_to_cicd" {
  for_each                  = var.spoke_vnet_ids
  name                      = "peer-${each.key}-to-cicd"
  resource_group_name       = split("/", each.value)[4]
  virtual_network_name      = split("/", each.value)[8]
  remote_virtual_network_id = azurerm_virtual_network.cicd.id
  allow_forwarded_traffic   = true
}

# --- Subnets ---
# Container App Environment subnet — replaces ACI agents subnet
resource "azurerm_subnet" "container_app" {
  name                 = "container-app"
  resource_group_name  = azurerm_resource_group.cicd.name
  virtual_network_name = azurerm_virtual_network.cicd.name
  address_prefixes     = [var.container_app_subnet_cidr]

  delegation {
    name = "Microsoft.App.environments"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Associate NAT Gateway with Container App subnet for outbound connectivity.
# Container App delegated subnets do not support UDRs, so NAT Gateway is the only outbound path.
resource "azurerm_subnet_nat_gateway_association" "container_app" {
  subnet_id      = azurerm_subnet.container_app.id
  nat_gateway_id = azurerm_nat_gateway.cicd.id
}

resource "azurerm_subnet" "aci_agents_acr" {
  name                 = "aci-agents-acr"
  resource_group_name  = azurerm_resource_group.cicd.name
  virtual_network_name = azurerm_virtual_network.cicd.name
  address_prefixes     = [var.aci_agents_acr_subnet_cidr]
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "private-endpoints"
  resource_group_name  = azurerm_resource_group.cicd.name
  virtual_network_name = azurerm_virtual_network.cicd.name
  address_prefixes     = [var.private_endpoints_subnet_cidr]
}

# --- NAT Gateway (self-managed) ---
# Created before the AVM module to associate with Container App subnet.
# Container App delegated subnets don't support UDRs, so NAT Gateway is the only outbound path.
resource "azurerm_public_ip" "nat" {
  name                = "pip-natgw-cicd-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.cicd.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

resource "azurerm_nat_gateway" "cicd" {
  name                = "natgw-cicd-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.cicd.name
  location            = var.location
  sku_name            = "Standard"
  tags                = local.common_tags
}

resource "azurerm_nat_gateway_public_ip_association" "cicd" {
  nat_gateway_id       = azurerm_nat_gateway.cicd.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

# State moves: adopt module-created NAT Gateway resources into self-managed
moved {
  from = module.cicd_agents.azurerm_nat_gateway.this[0]
  to   = azurerm_nat_gateway.cicd
}
moved {
  from = module.cicd_agents.azurerm_public_ip.this[0]
  to   = azurerm_public_ip.nat
}
moved {
  from = module.cicd_agents.azurerm_nat_gateway_public_ip_association.this[0]
  to   = azurerm_nat_gateway_public_ip_association.cicd
}

# --- Random suffix for globally unique ACR name ---
resource "random_string" "acr_suffix" {
  length  = 6
  special = false
  upper   = false
}

# --- Managed Identity ---
# UAMI for Container App Job agents — authenticates with ADO and accesses platform KV
resource "azurerm_user_assigned_identity" "cicd_agents" {
  name                = "uami-cicd-agents-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.cicd.name
  location            = var.location

  tags = local.common_tags
}

# Grant CI/CD agents read access to platform KV (SSH keys, platform secrets)
resource "azurerm_role_assignment" "cicd_agents_kv_reader" {
  count                = var.platform_key_vault_id != "" ? 1 : 0
  scope                = var.platform_key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.cicd_agents.principal_id
}

# =============================================================================
# CI/CD-Owned Private DNS Zones (bootstrap mode — no hub)
# =============================================================================
# When hub DNS zones are not provided, CI/CD creates its own zones linked to
# the CI/CD VNet. Azure default DNS (168.63.129.16) resolves zones linked to
# the querying VNet natively — no DNS resolver needed.
# Day 2: these zones are destroyed when hub zone IDs are populated in tfvars.

resource "azurerm_private_dns_zone" "blob" {
  count               = local.use_hub_blob_zone ? 0 : 1
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.cicd.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  count                 = local.use_hub_blob_zone ? 0 : 1
  name                  = "link-blob-cicd"
  resource_group_name   = azurerm_resource_group.cicd.name
  private_dns_zone_name = azurerm_private_dns_zone.blob[0].name
  virtual_network_id    = azurerm_virtual_network.cicd.id
}

resource "azurerm_private_dns_zone" "vault" {
  count               = local.use_hub_vault_zone ? 0 : 1
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.cicd.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "vault" {
  count                 = local.use_hub_vault_zone ? 0 : 1
  name                  = "link-vault-cicd"
  resource_group_name   = azurerm_resource_group.cicd.name
  private_dns_zone_name = azurerm_private_dns_zone.vault[0].name
  virtual_network_id    = azurerm_virtual_network.cicd.id
}

resource "azurerm_private_dns_zone" "acr" {
  count               = local.use_hub_acr_zone ? 0 : 1
  name                = "privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.cicd.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  count                 = local.use_hub_acr_zone ? 0 : 1
  name                  = "link-acr-cicd"
  resource_group_name   = azurerm_resource_group.cicd.name
  private_dns_zone_name = azurerm_private_dns_zone.acr[0].name
  virtual_network_id    = azurerm_virtual_network.cicd.id
}

# =============================================================================
# Private Endpoints — CI/CD SA, Hub+Spoke SA, Platform KV
# DNS zone IDs resolved via locals: hub zones when available, CI/CD-owned otherwise.
# =============================================================================

# CI/CD State SA private endpoint
resource "azurerm_private_endpoint" "state_sa" {
  count               = local.state_sa_enabled ? 1 : 0
  name                = "pe-tfstate-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.cicd.name
  location            = var.location
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = local.common_tags

  private_service_connection {
    name                           = "psc-tfstate-${var.environment}-${local.location_code}"
    private_connection_resource_id = var.state_storage_account_id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [local.blob_dns_zone_id]
  }
}

# Hub+Spoke State SA private endpoint (Day 2 — after hub exists, self-hosted agents access this)
resource "azurerm_private_endpoint" "hub_spoke_state_sa" {
  count               = local.hub_spoke_state_sa_enabled ? 1 : 0
  name                = "pe-tfstate-hubspoke-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.cicd.name
  location            = var.location
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = local.common_tags

  private_service_connection {
    name                           = "psc-tfstate-hubspoke-${var.environment}-${local.location_code}"
    private_connection_resource_id = var.hub_spoke_state_storage_account_id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [local.blob_dns_zone_id]
  }
}

# Platform KV private endpoint
resource "azurerm_private_endpoint" "platform_kv" {
  count               = var.platform_key_vault_id != "" ? 1 : 0
  name                = "pe-kvplatform-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.cicd.name
  location            = var.location
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = local.common_tags

  private_service_connection {
    name                           = "psc-kvplatform-${var.environment}-${local.location_code}"
    private_connection_resource_id = var.platform_key_vault_id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [local.vault_dns_zone_id]
  }
}

# =============================================================================
# AVM CI/CD Agents Module — Container App Jobs with KEDA auto-scaling
# =============================================================================
module "cicd_agents" {
  source  = "Azure/avm-ptn-cicd-agents-and-runners/azurerm"
  version = "~> 0.5"

  postfix = "cicd-${var.environment}"

  # Use self-created resource group
  resource_group_creation_enabled = false
  resource_group_name             = azurerm_resource_group.cicd.name
  location                        = var.location

  # Compute type: Container App Jobs with KEDA auto-scaling (0 to N on demand)
  compute_types                    = ["azure_container_app"]
  virtual_network_creation_enabled = false
  virtual_network_id               = azurerm_virtual_network.cicd.id
  container_app_subnet_id          = azurerm_subnet.container_app.id
  use_default_container_image      = true
  use_private_networking           = true
  use_zone_redundancy              = false
  container_app_container_cpu      = var.container_app_cpu
  container_app_container_memory   = var.container_app_memory

  # KEDA auto-scaling: scale 0 to max_execution_count based on queue demand
  container_app_max_execution_count      = var.container_app_max_execution_count
  container_app_min_execution_count      = var.container_app_min_execution_count
  container_app_polling_interval_seconds = var.container_app_polling_interval

  # ACR name must be globally unique (alphanumeric only)
  container_registry_name = "acrcicd${var.environment}${local.location_code}${random_string.acr_suffix.result}"

  # ACR private endpoint — uses hub zone when available, CI/CD-owned zone at bootstrap
  container_registry_private_dns_zone_creation_enabled = false
  container_registry_dns_zone_id                       = local.acr_dns_zone_id
  container_registry_private_endpoint_subnet_id        = azurerm_subnet.aci_agents_acr.id

  # ADO configuration
  version_control_system_type         = "azuredevops"
  version_control_system_organization = var.ado_organization_url
  version_control_system_pool_name    = var.ado_agent_pool_name

  # Auth: UAMI — no PAT tokens (requires UAMI in ADO Project Collection Service Accounts)
  version_control_system_authentication_method    = "uami"
  version_control_system_personal_access_token    = null
  user_assigned_managed_identity_creation_enabled = false
  user_assigned_managed_identity_id               = azurerm_user_assigned_identity.cicd_agents.id
  user_assigned_managed_identity_client_id        = azurerm_user_assigned_identity.cicd_agents.client_id
  user_assigned_managed_identity_principal_id     = azurerm_user_assigned_identity.cicd_agents.principal_id

  # Log Analytics — use hub workspace when available, let module create otherwise
  log_analytics_workspace_creation_enabled = var.hub_log_analytics_workspace_id == ""
  log_analytics_workspace_id               = var.hub_log_analytics_workspace_id != "" ? var.hub_log_analytics_workspace_id : null

  # NAT Gateway — self-managed (created above, passed to module)
  nat_gateway_creation_enabled = false
  nat_gateway_id               = azurerm_nat_gateway.cicd.id
  public_ip_creation_enabled   = false
  public_ip_id                 = azurerm_public_ip.nat.id

  enable_telemetry = true
  tags             = local.common_tags

  depends_on = [
    azurerm_subnet.container_app,
    azurerm_subnet.aci_agents_acr,
    azurerm_nat_gateway_public_ip_association.cicd,
    azurerm_subnet_nat_gateway_association.container_app,
  ]
}
