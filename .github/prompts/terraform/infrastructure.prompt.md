# Terraform Infrastructure Code Patterns

This file contains Terraform code patterns and templates referenced by the `terraform/generate-from-json` skill when generating infrastructure code from flexible JSON schema.

## Purpose

The skill reads this file to obtain code templates for:
- Hub resources (VNet, Firewall, Bastion, DNS zones, Application Gateway)
- Spoke types: aks, data, integration, sharedServices, other
- Provider configurations
- Output patterns

## Hub Code Patterns

### Hub VNet with Azure Verified Module

```hcl
module "hub_vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "~> 0.4"
  
  name                = "vnet-hub-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location
  address_space       = var.hub_vnet_address_space
  
  subnets = {
    AzureFirewallSubnet = {
      address_prefixes = ["10.0.1.0/26"]
    }
    AzureBastionSubnet = {
      address_prefixes = ["10.0.2.0/27"]
    }
    GatewaySubnet = {
      address_prefixes = ["10.0.3.0/27"]
    }
    management = {
      address_prefixes = ["10.0.4.0/24"]
    }
    AppGatewaySubnet = {  # For Tier 1 App Gateway
      address_prefixes = ["10.0.5.0/26"]
    }
  }
  
  enable_telemetry = true
  tags             = local.common_tags
}
```

### Azure Firewall

```hcl
module "firewall" {
  count   = var.deploy_firewall ? 1 : 0
  source  = "Azure/avm-res-network-azurefirewall/azurerm"
  version = "~> 0.3"
  
  name                        = "afw-hub-${var.environment}-${local.location_code}"
  resource_group_name         = azurerm_resource_group.hub.name
  location                    = var.location
  firewall_sku_tier           = var.firewall_sku_tier
  firewall_sku_name           = "AZFW_VNet"
  firewall_zones              = var.firewall_availability_zones
  firewall_subnet_id          = module.hub_vnet.subnets["AzureFirewallSubnet"].resource_id
  firewall_public_ip_count    = 1
  
  enable_telemetry = true
  tags             = local.common_tags
}
```

### Azure Bastion

```hcl
module "bastion" {
  source  = "Azure/avm-res-network-bastionhost/azurerm"
  version = "~> 0.3"
  
  name                = "bas-hub-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location
  subnet_id           = module.hub_vnet.subnets["AzureBastionSubnet"].resource_id
  sku                 = var.bastion_sku
  
  enable_telemetry = true
  tags             = local.common_tags
}
```

### Log Analytics Workspace

```hcl
module "log_analytics" {
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "~> 0.4"
  
  name                = "law-hub-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location
  
  log_analytics_workspace_retention_in_days = var.log_retention_days
  log_analytics_workspace_sku               = var.log_analytics_sku
  
  enable_telemetry = true
  tags             = local.common_tags
}
```

### Private DNS Zones

```hcl
module "private_dns_zones" {
  for_each = toset(var.private_dns_zones)
  
  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "~> 0.2"
  
  domain_name         = each.value
  resource_group_name = azurerm_resource_group.hub.name
  
  virtual_network_links = {
    hub_vnet = {
      vnetlinkname = "link-${each.value}-hub"
      vnetid       = module.hub_vnet.resource_id
    }
  }
  
  enable_telemetry = true
  tags             = local.common_tags
}
```

### Application Gateway (Tier 1 Ingress)

```hcl
module "application_gateway" {
  count   = var.deploy_application_gateway ? 1 : 0
  source  = "Azure/avm-res-network-applicationgateway/azurerm"
  version = "~> 0.4"
  
  name                = "agw-hub-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location
  
  sku = {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 2
  }
  
  gateway_ip_configurations = [{
    name      = "gateway-ip-config"
    subnet_id = module.hub_vnet.subnets["AppGatewaySubnet"].resource_id
  }]
  
  frontend_ip_configurations = var.app_gateway_frontend_type == "public" ? [
    {
      name                 = "public-frontend"
      public_ip_address_id = azurerm_public_ip.app_gateway[0].id
    }
  ] : [
    {
      name                          = "private-frontend"
      subnet_id                     = module.hub_vnet.subnets["AppGatewaySubnet"].resource_id
      private_ip_address_allocation = "Static"
      private_ip_address            = var.app_gateway_private_ip
    }
  ]
  
  frontend_ports = [
    { name = "port-443", port = 443 },
    { name = "port-80", port = 80 }
  ]
  
  backend_address_pools = [
    { name = "backend-tier2" }  # Configure after spoke deployment
  ]
  
  backend_http_settings = [{
    name                  = "http-settings-443"
    cookie_based_affinity = "Disabled"
    port                  = 443
    protocol              = "Https"
    request_timeout       = 30
  }]
  
  http_listeners = [{
    name                           = "listener-https"
    frontend_ip_configuration_name = "public-frontend"
    frontend_port_name             = "port-443"
    protocol                       = "Https"
  }]
  
  request_routing_rules = [{
    name                       = "routing-rule-https"
    rule_type                  = "Basic"
    http_listener_name         = "listener-https"
    backend_address_pool_name  = "backend-tier2"
    backend_http_settings_name = "http-settings-443"
    priority                   = 100
  }]
  
  waf_configuration = {
    enabled          = true
    firewall_mode    = "Prevention"
    rule_set_type    = "OWASP"
    rule_set_version = "3.2"
  }
  
  enable_telemetry = true
  tags             = local.common_tags
}
```

### Hub Outputs

```hcl
output "hub_vnet_id" {
  description = "Hub VNet resource ID"
  value       = module.hub_vnet.resource_id
}

output "hub_vnet_name" {
  description = "Hub VNet name"
  value       = module.hub_vnet.name
}

output "firewall_private_ip" {
  description = "Azure Firewall private IP address"
  value       = var.deploy_firewall ? module.firewall[0].private_ip_address : null
}

output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace resource ID"
  value       = module.log_analytics.resource_id
}

output "private_dns_zone_ids" {
  description = "Map of private DNS zone names to resource IDs"
  value       = { for zone, zone_module in module.private_dns_zones : zone => zone_module.resource_id }
}

output "bastion_id" {
  description = "Bastion resource ID"
  value       = module.bastion.resource_id
}

output "app_gateway_id" {
  description = "Application Gateway resource ID (if deployed)"
  value       = var.deploy_application_gateway ? module.application_gateway[0].resource_id : null
}
```

## Spoke Type: aks

### AKS Cluster with Azure Verified Module

```hcl
module "aks_cluster" {
  source  = "Azure/avm-res-containerservice-managedcluster/azurerm"
  version = "~> 0.3"
  
  name                = "aks-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.spoke.name
  location            = var.location
  
  kubernetes_version = var.kubernetes_version
  sku_tier           = var.aks_sku_tier
  
  network_profile = {
    network_plugin      = var.network_plugin
    network_plugin_mode = var.network_plugin_mode
    network_dataplane   = var.network_dataplane
    network_policy      = var.network_policy
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    outbound_type       = var.outbound_type
  }
  
  default_node_pool = {
    name                = "system"
    vm_size             = var.system_node_pool_vm_size
    enable_auto_scaling = true
    min_count           = var.system_node_pool_min_count
    max_count           = var.system_node_pool_max_count
    vnet_subnet_id      = module.spoke_vnet.subnets["aks_system"].resource_id
    availability_zones  = var.availability_zones
  }
  
  private_cluster_enabled = var.private_cluster_enabled
  
  identity = {
    type = "SystemAssigned"
  }
  
  monitor_metrics = {
    enabled = true
  }
  
  oms_agent = {
    log_analytics_workspace_id = local.hub_outputs.log_analytics_workspace_id.value
  }
  
  workload_identity_enabled = true
  oidc_issuer_enabled       = true
  
  enable_telemetry = true
  tags             = local.common_tags
}

# User node pools
resource "azurerm_kubernetes_cluster_node_pool" "user_pools" {
  for_each = { for pool in var.user_node_pools : pool.name => pool }
  
  name                  = each.value.name
  kubernetes_cluster_id = module.aks_cluster.resource_id
  vm_size               = each.value.vm_size
  enable_auto_scaling   = true
  min_count             = each.value.min_count
  max_count             = each.value.max_count
  vnet_subnet_id        = module.spoke_vnet.subnets["aks_user"].resource_id
  zones                 = var.availability_zones
  
  tags = local.common_tags
}
```

### Spoke VNet and Peering

```hcl
module "spoke_vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "~> 0.4"
  
  name                = "vnet-spoke-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.spoke.name
  location            = var.location
  address_space       = var.spoke_vnet_address_space
  
  subnets = {
    aks_system = {
      address_prefixes = var.aks_system_subnet_prefix
    }
    aks_user = {
      address_prefixes = var.aks_user_subnet_prefix
    }
    private_endpoints = {
      address_prefixes = var.private_endpoints_subnet_prefix
    }
  }
  
  enable_telemetry = true
  tags             = local.common_tags
}

# VNet Peering to Hub
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "peer-spoke-to-hub"
  resource_group_name       = azurerm_resource_group.spoke.name
  virtual_network_name      = module.spoke_vnet.name
  remote_virtual_network_id = local.hub_outputs.hub_vnet_id.value
  
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                      = "peer-hub-to-spoke"
  resource_group_name       = var.hub_resource_group_name
  virtual_network_name      = local.hub_outputs.hub_vnet_name.value
  remote_virtual_network_id = module.spoke_vnet.resource_id
  
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false
}
```

### Route Table with UDR to Firewall

```hcl
resource "azurerm_route_table" "spoke" {
  name                = "rt-spoke-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.spoke.name
  location            = var.location
  
  route {
    name                   = "route-to-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.hub_outputs.firewall_private_ip.value
  }
  
  tags = local.common_tags
}

resource "azurerm_subnet_route_table_association" "aks_system" {
  subnet_id      = module.spoke_vnet.subnets["aks_system"].resource_id
  route_table_id = azurerm_route_table.spoke.id
}

resource "azurerm_subnet_route_table_association" "aks_user" {
  subnet_id      = module.spoke_vnet.subnets["aks_user"].resource_id
  route_table_id = azurerm_route_table.spoke.id
}
```

## Spoke Type: data

### Storage Account with Private Endpoint

```hcl
module "storage_account" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "~> 0.2"
  
  name                = "st${var.environment}${local.location_code}001"
  resource_group_name = azurerm_resource_group.spoke.name
  location            = var.location
  
  account_tier             = "Standard"
  account_replication_type = var.storage_replication_type
  
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"
  
  public_network_access_enabled = false
  
  network_rules = {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
  
  private_endpoints = {
    blob = {
      subnet_id            = module.spoke_vnet.subnets["private_endpoints"].resource_id
      private_dns_zone_ids = [local.hub_outputs.private_dns_zone_ids.value["privatelink.blob.core.windows.net"]]
    }
    file = {
      subnet_id            = module.spoke_vnet.subnets["private_endpoints"].resource_id
      private_dns_zone_ids = [local.hub_outputs.private_dns_zone_ids.value["privatelink.file.core.windows.net"]]
    }
  }
  
  enable_telemetry = true
  tags             = local.common_tags
}
```

### Azure SQL Database with Private Endpoint

```hcl
module "sql_server" {
  source  = "Azure/avm-res-sql-server/azurerm"
  version = "~> 0.2"
  
  name                = "sql-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.spoke.name
  location            = var.location
  
  administrator_login          = var.sql_admin_login
  administrator_login_password = var.sql_admin_password  # Use Key Vault reference
  version                      = "12.0"
  
  public_network_access_enabled = false
  
  azuread_administrator = {
    login_username = var.sql_aad_admin_login
    object_id      = var.sql_aad_admin_object_id
  }
  
  private_endpoints = {
    default = {
      subnet_id            = module.spoke_vnet.subnets["private_endpoints"].resource_id
      private_dns_zone_ids = [local.hub_outputs.private_dns_zone_ids.value["privatelink.database.windows.net"]]
    }
  }
  
  enable_telemetry = true
  tags             = local.common_tags
}

resource "azurerm_mssql_database" "main" {
  name      = "db-${var.environment}"
  server_id = module.sql_server.resource_id
  
  sku_name                    = var.sql_database_sku
  max_size_gb                 = var.sql_database_max_size_gb
  zone_redundant              = var.environment == "prod" ? true : false
  geo_backup_enabled          = var.environment == "prod" ? true : false
  auto_pause_delay_in_minutes = var.environment == "dev" ? 60 : -1
  
  tags = local.common_tags
}
```

## Spoke Type: integration

### Service Bus with Private Endpoint

```hcl
module "service_bus" {
  source  = "Azure/avm-res-servicebus-namespace/azurerm"
  version = "~> 0.2"
  
  name                = "sb-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.spoke.name
  location            = var.location
  
  sku      = var.service_bus_sku
  capacity = var.service_bus_capacity
  
  public_network_access_enabled = false
  
  private_endpoints = {
    default = {
      subnet_id            = module.spoke_vnet.subnets["private_endpoints"].resource_id
      private_dns_zone_ids = [local.hub_outputs.private_dns_zone_ids.value["privatelink.servicebus.windows.net"]]
    }
  }
  
  enable_telemetry = true
  tags             = local.common_tags
}
```

### Event Hubs with Private Endpoint

```hcl
module "event_hubs" {
  source  = "Azure/avm-res-eventhub-namespace/azurerm"
  version = "~> 0.3"
  
  name                = "evh-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.spoke.name
  location            = var.location
  
  sku      = var.event_hubs_sku
  capacity = var.event_hubs_capacity
  
  public_network_access_enabled = false
  
  private_endpoints = {
    default = {
      subnet_id            = module.spoke_vnet.subnets["private_endpoints"].resource_id
      private_dns_zone_ids = [local.hub_outputs.private_dns_zone_ids.value["privatelink.servicebus.windows.net"]]
    }
  }
  
  enable_telemetry = true
  tags             = local.common_tags
}
```

## Spoke Type: sharedServices

### Azure Container Registry with Private Endpoint

```hcl
module "container_registry" {
  source  = "Azure/avm-res-containerregistry-registry/azurerm"
  version = "~> 0.3"
  
  name                = "acr${var.environment}${local.location_code}"
  resource_group_name = azurerm_resource_group.spoke.name
  location            = var.location
  
  sku = var.acr_sku
  
  admin_enabled          = false
  public_network_enabled = false
  
  zone_redundancy_enabled = var.environment == "prod" ? true : false
  
  private_endpoints = {
    default = {
      subnet_id            = module.spoke_vnet.subnets["private_endpoints"].resource_id
      private_dns_zone_ids = [local.hub_outputs.private_dns_zone_ids.value["privatelink.azurecr.io"]]
    }
  }
  
  enable_telemetry = true
  tags             = local.common_tags
}
```

### Azure Key Vault with Private Endpoint

```hcl
module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "~> 0.9"
  
  name                = "kv-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.spoke.name
  location            = var.location
  
  tenant_id = data.azurerm_client_config.current.tenant_id
  
  sku_name = "standard"
  
  public_network_access_enabled = false
  
  network_acls = {
    bypass         = "AzureServices"
    default_action = "Deny"
  }
  
  private_endpoints = {
    default = {
      subnet_id            = module.spoke_vnet.subnets["private_endpoints"].resource_id
      private_dns_zone_ids = [local.hub_outputs.private_dns_zone_ids.value["privatelink.vaultcore.azure.net"]]
    }
  }
  
  enable_telemetry = true
  tags             = local.common_tags
}
```

## Provider Configuration Patterns

### Single Subscription

```hcl
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
  }
}
```

### Multi-Subscription with Aliases

```hcl
provider "azurerm" {
  alias           = "hub-eastus"
  subscription_id = var.hub_subscription_id
  
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
  }
}

provider "azurerm" {
  alias           = "spoke-aks-prod"
  subscription_id = var.spoke_subscription_id
  
  features {}
}
```

## Hub Output Consumption Pattern

### In Spoke data-sources.tf

```hcl
locals {
  hub_outputs = jsondecode(file("../hub-${var.hub_name}/${var.hub_name}-outputs.json"))
}

# Access values (note .value accessor for terraform output -json format)
# local.hub_outputs.firewall_private_ip.value
# local.hub_outputs.log_analytics_workspace_id.value
# local.hub_outputs.private_dns_zone_ids.value["privatelink.azurecr.io"]
```

## Common Locals Pattern

```hcl
locals {
  location_code = {
    "eastus"        = "eus"
    "westus"        = "wus"
    "centralus"     = "cus"
    "southcentralus"= "scus"
    "westeurope"    = "weu"
    "northeurope"   = "neu"
  }[var.location]
  
  common_tags = merge(
    var.global_required_tags,
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      CreatedOn   = formatdate("YYYY-MM-DD", timestamp())
    }
  )
}
```

## Terraform Backend Configuration Pattern

```hcl
# backend-dev.tfbackend
resource_group_name  = "rg-terraform-state-dev"
storage_account_name = "sttfstatedev"
container_name       = "tfstate"
key                  = "hub-eastus-dev.tfstate"
use_oidc            = true
```

## Notes

- All modules use Azure Verified Modules (AVM) from Terraform Registry
- Version pinning with `~>` syntax allows patch updates
- `enable_telemetry = true` on all AVM modules
- All resources tagged with `local.common_tags`
- Private endpoints use hub Private DNS zones for name resolution
- Multi-subscription scenarios use provider aliases
- Hub outputs consumed via file-based JSON pattern

## References

- **Skill**: `.claude/skills/terraform/generate-from-json/SKILL.md`
- **Mapping Instructions**: `.github/instructions/terraform-flexible-json-mapping.instructions.md`
- **AVM Standards**: `.github/instructions/azure-verified-modules-terraform.instructions.md`
- **Terraform Best Practices**: `.github/instructions/generate-modern-terraform-code-for-azure.instructions.md`
