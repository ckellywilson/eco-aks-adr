# CI/CD Landing Zone Production Environment Variables
subscription_id = "f8a5f387-2f0b-42f5-b71f-5ee02b8967cf"

environment = "prod"
location    = "eastus2"

# CI/CD resource group and VNet (self-contained, not hub-managed)
cicd_resource_group_name = "rg-cicd-eus2-prod"
cicd_vnet_name           = "vnet-cicd-prod-eus2"
cicd_vnet_address_space  = ["10.2.0.0/24"]

# ADO configuration
ado_organization_url = "https://dev.azure.com/modenv496195"
ado_agent_pool_name  = "aci-cicd-pool"

# Container App Job settings (KEDA auto-scaling: 0 to N on demand)
container_app_max_execution_count = 10
container_app_min_execution_count = 0
container_app_polling_interval    = 30
container_app_cpu                 = 2
container_app_memory              = "4Gi"

# Subnet CIDRs within CI/CD VNet (10.2.0.0/24)
container_app_subnet_cidr     = "10.2.0.0/27"
aci_agents_acr_subnet_cidr    = "10.2.0.32/29"
private_endpoints_subnet_cidr = "10.2.0.48/28"

# CI/CD Terraform state storage account (PE for self-hosted agent access)
state_storage_account_id = "/subscriptions/f8a5f387-2f0b-42f5-b71f-5ee02b8967cf/resourceGroups/rg-cicd-eus2-prod/providers/Microsoft.Storage/storageAccounts/stcicdeus2d2c496b3"

# Platform Key Vault (set via pipeline variable or manually)
# platform_key_vault_id = "<set-by-pipeline-or-manually>"

# =============================================================================
# Hub Integration — Day 2 (leave empty/commented for bootstrap, populate after hub exists)
# =============================================================================
# After hub is deployed, populate these values and re-apply CI/CD to add:
#   - Bidirectional VNet peering (CI/CD ↔ hub)
#   - Custom DNS (hub resolver IP) replacing Azure default DNS
#   - Hub DNS zones replacing CI/CD-owned zones
#   - Hub+Spoke SA private endpoint for self-hosted agent access
#
# hub_vnet_id                        = "/subscriptions/.../providers/Microsoft.Network/virtualNetworks/vnet-hub-prod-eus2"
# hub_dns_resolver_ip                = "10.0.6.4"
# hub_acr_dns_zone_id                = "/subscriptions/.../providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io"
# hub_blob_dns_zone_id               = "/subscriptions/.../providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
# hub_vault_dns_zone_id              = "/subscriptions/.../providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
# hub_log_analytics_workspace_id     = "/subscriptions/.../providers/Microsoft.OperationalInsights/workspaces/law-hub-prod-eus2"
# hub_spoke_state_storage_account_id = "/subscriptions/.../providers/Microsoft.Storage/storageAccounts/<hub-spoke-sa-name>"

# Resource tags
tags = {
  Purpose     = "AKS Landing Zone CI/CD"
  ManagedBy   = "Terraform"
  Environment = "prod"
}
