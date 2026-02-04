# Terraform Flexible JSON Mapping Instructions

**File Purpose**: Defines rules for mapping flexible JSON schema to Terraform infrastructure code using Azure Verified Modules (AVM).

**Applies To**: `.claude/skills/terraform/generate-from-json/SKILL.md`

---

## Overview

These instructions define how to map the flexible JSON schema (documented in `.github/docs/customer-config-schema.md`) to production-ready Terraform code. The mapping process creates segregated folder structures for hubs and spokes with Azure Verified Modules.

---

## JSON Schema Structure

The flexible JSON schema consists of four main sections:

1. **metadata** - Customer and workshop context
2. **globalConstraints** - Cross-cutting configuration
3. **topology** - Network architecture (hubs[], spokes[])
4. **aksDesign** - AKS cluster specifications

---

## Hub Mapping Rules

### Hub Directory Structure

**JSON Input:**
```json
{
  "topology": {
    "hubs": [
      {
        "name": "hub-eastus",
        "subscriptionId": "aaaa-bbbb-cccc-dddd",
        "resourceGroup": "rg-hub-eastus-prod",
        "region": "eastus",
        "networking": { /* ... */ },
        "identity": { /* ... */ },
        "security": { /* ... */ },
        "operations": { /* ... */ }
      }
    ]
  }
}
```

**Generated Structure:**
```
infra/terraform/hub-eastus/
├── main.tf
├── variables.tf
├── outputs.tf
├── providers.tf
├── terraform.tf
├── locals.tf
├── data-sources.tf (if needed)
├── backend-dev.tfbackend
├── backend-prod.tfbackend
├── dev.tfvars
├── prod.tfvars
├── deploy.sh
├── hub-eastus-outputs.json (generated after apply)
└── README.md
```

### Hub Networking Mapping

**VNet Address Spaces:**
```json
"networking": {
  "addressSpaces": ["10.0.0.0/16"]
}
```

→

```hcl
module "hub_vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "~> 0.4"
  
  name                = "vnet-hub-eastus-prod"
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location
  address_space       = ["10.0.0.0/16"]
  
  enable_telemetry = true
  tags             = local.common_tags
}
```

**Subnets:**
```json
"networking": {
  "subnets": [
    {
      "name": "AzureFirewallSubnet",
      "addressPrefix": "10.0.1.0/26",
      "purpose": "firewall"
    },
    {
      "name": "AzureBastionSubnet",
      "addressPrefix": "10.0.2.0/27",
      "purpose": "bastion"
    }
  ]
}
```

→

```hcl
module "hub_vnet" {
  # ... other config ...
  
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
  }
}
```

**Firewall Deployment:**
```json
"firewallType": "AzureFirewall"
```

→

```hcl
module "firewall" {
  count   = var.deploy_firewall ? 1 : 0
  source  = "Azure/avm-res-network-azurefirewall/azurerm"
  version = "~> 0.3"
  
  name                        = "afw-hub-eastus-prod"
  resource_group_name         = azurerm_resource_group.hub.name
  location                    = var.location
  firewall_sku_tier           = "Standard"
  firewall_sku_name           = "AZFW_VNet"
  firewall_zones              = ["1", "2", "3"]
  firewall_subnet_id          = module.hub_vnet.subnets["AzureFirewallSubnet"].resource_id
  firewall_public_ip_count    = 1
  
  enable_telemetry = true
  tags             = local.common_tags
}
```

**Bastion Deployment:**

Always deploy Bastion in hub (baseline requirement).

→

```hcl
module "bastion" {
  source  = "Azure/avm-res-network-bastionhost/azurerm"
  version = "~> 0.3"
  
  name                = "bas-hub-eastus-prod"
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location
  subnet_id           = module.hub_vnet.subnets["AzureBastionSubnet"].resource_id
  sku                 = "Standard"
  
  enable_telemetry = true
  tags             = local.common_tags
}
```

**Private DNS Zones:**
```json
"dnsModel": "AzurePrivateDNS",
"networking": {
  "privateDnsZones": [
    "privatelink.azurecr.io",
    "privatelink.vaultcore.azure.net"
  ]
}
```

→

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

### Hub Operations Mapping

**Log Analytics:**
```json
"operations": {
  "logAnalyticsWorkspaceId": "/subscriptions/.../workspaces/law-hub",
  "monitoringTools": ["AzureMonitor"]
}
```

→

```hcl
module "log_analytics" {
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "~> 0.4"
  
  name                = "law-hub-eastus-prod"
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location
  
  log_analytics_workspace_retention_in_days = 30
  log_analytics_workspace_sku               = "PerGB2018"
  
  enable_telemetry = true
  tags             = local.common_tags
}
```

### Hub Outputs

**Required Outputs** (written to `{hub-name}-outputs.json`):

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
```

---

## Spoke Mapping Rules

### Spoke Directory Structure

**JSON Input:**
```json
{
  "topology": {
    "spokes": [
      {
        "name": "spoke-aks-prod",
        "type": "aks",
        "subscriptionId": "ffff-gggg-hhhh-iiii",
        "resourceGroup": "rg-spoke-aks-prod",
        "region": "eastus",
        "hubName": "hub-eastus",
        "networking": { /* ... */ },
        "resources": [ /* ... */ ]
      }
    ]
  }
}
```

**Generated Structure:**
```
infra/terraform/spoke-aks-prod/
├── main.tf
├── variables.tf
├── outputs.tf
├── data-sources.tf  # Reads hub outputs
├── providers.tf
├── terraform.tf
├── locals.tf
├── backend-dev.tfbackend
├── backend-prod.tfbackend
├── dev.tfvars
├── prod.tfvars
├── deploy.sh
└── README.md
```

### Spoke Hub Dependency

**Hub Outputs Consumption:**

```hcl
# data-sources.tf
locals {
  hub_outputs = jsondecode(file("../hub-${var.hub_name}/${var.hub_name}-outputs.json"))
}

# Usage in main.tf
resource "azurerm_route" "to_firewall" {
  name                   = "route-to-firewall"
  resource_group_name    = azurerm_resource_group.spoke.name
  route_table_name       = azurerm_route_table.spoke.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = local.hub_outputs.firewall_private_ip.value
}
```

### Spoke Networking Mapping

**VNet and Subnets:**
```json
"networking": {
  "vnetName": "vnet-spoke-aks-prod",
  "addressSpaces": ["10.1.0.0/16"],
  "subnets": [
    {
      "name": "aks-system",
      "addressPrefix": "10.1.0.0/23",
      "purpose": "aksSystem"
    },
    {
      "name": "aks-user",
      "addressPrefix": "10.1.2.0/23",
      "purpose": "aksNodePool"
    }
  ]
}
```

→

```hcl
module "spoke_vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "~> 0.4"
  
  name                = "vnet-spoke-aks-prod"
  resource_group_name = azurerm_resource_group.spoke.name
  location            = var.location
  address_space       = ["10.1.0.0/16"]
  
  subnets = {
    aks_system = {
      address_prefixes = ["10.1.0.0/23"]
    }
    aks_user = {
      address_prefixes = ["10.1.2.0/23"]
    }
  }
  
  enable_telemetry = true
  tags             = local.common_tags
}
```

**VNet Peering (Same Subscription):**
```json
"peeringToHub": true
```

→

```hcl
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "peer-spoke-to-hub"
  resource_group_name       = azurerm_resource_group.spoke.name
  virtual_network_name      = module.spoke_vnet.name
  remote_virtual_network_id = local.hub_outputs.hub_vnet_id
  
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                      = "peer-hub-to-spoke"
  resource_group_name       = var.hub_resource_group_name
  virtual_network_name      = local.hub_outputs.hub_vnet_name
  remote_virtual_network_id = module.spoke_vnet.resource_id
  
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false
}
```

**VNet Peering (Cross-Subscription):**
```json
"spoke.subscriptionId": "ffff-gggg-hhhh-iiii",
"hub.subscriptionId": "aaaa-bbbb-cccc-dddd"
```

→

```hcl
# In spoke main.tf (using spoke provider)
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  provider                = azurerm.spoke-aks-prod
  name                    = "peer-spoke-to-hub"
  resource_group_name     = azurerm_resource_group.spoke.name
  virtual_network_name    = module.spoke_vnet.name
  remote_virtual_network_id = local.hub_outputs.hub_vnet_id
  
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

# In hub main.tf (using hub provider) - OR in spoke with hub provider alias
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  provider                = azurerm.hub-eastus
  name                    = "peer-hub-to-spoke-aks"
  resource_group_name     = var.hub_resource_group_name
  virtual_network_name    = local.hub_outputs.hub_vnet_name
  remote_virtual_network_id = module.spoke_vnet.resource_id
  
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false
}
```

### Spoke Type-Specific Mapping

#### Type: aks

**Default Resources (if `resources[]` empty):**
- AKS cluster with configuration from `aksDesign.clusters[]`
- System node pool
- User node pools
- Monitoring integration

**AKS Cluster from aksDesign:**
```json
"aksDesign": {
  "clusters": [
    {
      "name": "aks-prod-001",
      "spokeName": "spoke-aks-prod",
      "clusterSku": "Standard",
      "kubernetesVersion": "1.29",
      "networkPlugin": "azure",
      "networkPluginMode": "overlay",
      "networkPolicy": "cilium",
      "networkDataplane": "cilium",
      "podCidr": "192.168.0.0/16",
      "serviceCidr": "10.2.0.0/16",
      "dnsServiceIp": "10.2.0.10",
      "outboundType": "userDefinedRouting",
      "privateClusterEnabled": true,
      "nodePools": [
        {
          "name": "system",
          "mode": "system",
          "vmSize": "Standard_D4s_v5",
          "minCount": 3,
          "maxCount": 6
        }
      ]
    }
  ]
}
```

→

```hcl
module "aks_cluster" {
  source  = "Azure/avm-res-containerservice-managedcluster/azurerm"
  version = "~> 0.3"
  
  name                = "aks-prod-001"
  resource_group_name = azurerm_resource_group.spoke.name
  location            = var.location
  
  kubernetes_version = "1.29"
  sku_tier           = "Standard"
  
  network_profile = {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_dataplane   = "cilium"
    network_policy      = "cilium"
    pod_cidr            = "192.168.0.0/16"
    service_cidr        = "10.2.0.0/16"
    dns_service_ip      = "10.2.0.10"
    outbound_type       = "userDefinedRouting"
  }
  
  default_node_pool = {
    name                = "system"
    vm_size             = "Standard_D4s_v5"
    enable_auto_scaling = true
    min_count           = 3
    max_count           = 6
    vnet_subnet_id      = module.spoke_vnet.subnets["aks_system"].resource_id
  }
  
  private_cluster_enabled = true
  
  identity = {
    type = "SystemAssigned"
  }
  
  monitor_metrics = {
    enabled = true
  }
  
  oms_agent = {
    log_analytics_workspace_id = local.hub_outputs.log_analytics_workspace_id
  }
  
  enable_telemetry = true
  tags             = local.common_tags
}

# Additional user node pools
resource "azurerm_kubernetes_cluster_node_pool" "user_pools" {
  for_each = { for pool in var.user_node_pools : pool.name => pool }
  
  name                  = each.value.name
  kubernetes_cluster_id = module.aks_cluster.resource_id
  vm_size               = each.value.vm_size
  enable_auto_scaling   = true
  min_count             = each.value.min_count
  max_count             = each.value.max_count
  vnet_subnet_id        = module.spoke_vnet.subnets["aks_user"].resource_id
  
  tags = local.common_tags
}
```

#### Type: data

**Default Resources (if `resources[]` empty):**
- Storage account with private endpoint
- Azure SQL Database with private endpoint
- Private DNS zone links

**Explicit Resources from JSON:**
```json
"resources": [
  {
    "type": "storageAccount",
    "name": "stdataprod001",
    "sku": "Standard_LRS",
    "properties": {
      "accountTier": "Standard",
      "accountReplicationType": "LRS",
      "enableHttpsTrafficOnly": true
    }
  }
]
```

→

```hcl
module "storage_account" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "~> 0.2"
  
  name                = "stdataprod001"
  resource_group_name = azurerm_resource_group.spoke.name
  location            = var.location
  
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  https_traffic_only_enabled = true
  
  network_rules = {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
  
  private_endpoints = {
    blob = {
      subnet_id            = module.spoke_vnet.subnets["private_endpoints"].resource_id
      private_dns_zone_ids = [local.hub_outputs.private_dns_zone_ids["privatelink.blob.core.windows.net"]]
    }
  }
  
  enable_telemetry = true
  tags             = local.common_tags
}
```

#### Type: integration

**Default Resources (if `resources[]` empty):**
- Service Bus namespace with queues
- Event Hubs namespace
- Private endpoints

**Example Resource:**
```json
"resources": [
  {
    "type": "serviceBus",
    "name": "sb-integration-prod",
    "sku": "Premium",
    "properties": {
      "capacity": 1
    }
  }
]
```

→

```hcl
module "service_bus" {
  source  = "Azure/avm-res-servicebus-namespace/azurerm"
  version = "~> 0.2"
  
  name                = "sb-integration-prod"
  resource_group_name = azurerm_resource_group.spoke.name
  location            = var.location
  
  sku      = "Premium"
  capacity = 1
  
  private_endpoints = {
    default = {
      subnet_id            = module.spoke_vnet.subnets["private_endpoints"].resource_id
      private_dns_zone_ids = [local.hub_outputs.private_dns_zone_ids["privatelink.servicebus.windows.net"]]
    }
  }
  
  enable_telemetry = true
  tags             = local.common_tags
}
```

#### Type: sharedServices

**Default Resources (if `resources[]` empty):**
- Azure Container Registry with private endpoint
- Key Vault with private endpoint

**Example Resource:**
```json
"resources": [
  {
    "type": "containerRegistry",
    "name": "acrsharedprod",
    "sku": "Premium",
    "properties": {
      "adminUserEnabled": false,
      "publicNetworkAccess": "Disabled"
    }
  }
]
```

→

```hcl
module "container_registry" {
  source  = "Azure/avm-res-containerregistry-registry/azurerm"
  version = "~> 0.3"
  
  name                = "acrsharedprod"
  resource_group_name = azurerm_resource_group.spoke.name
  location            = var.location
  
  sku = "Premium"
  
  admin_enabled          = false
  public_network_enabled = false
  
  private_endpoints = {
    default = {
      subnet_id            = module.spoke_vnet.subnets["private_endpoints"].resource_id
      private_dns_zone_ids = [local.hub_outputs.private_dns_zone_ids["privatelink.azurecr.io"]]
    }
  }
  
  enable_telemetry = true
  tags             = local.common_tags
}
```

#### Type: other

**Default Resources (if `resources[]` empty):**
- VNet with subnets
- NSGs
- Route table
- VNet peering
- No application-specific resources

---
const subscriptions = new Map();

// From hubs
topology.hubs.forEach(hub => {
  if (!subscriptions.has(hub.subscriptionId)) {
    subscriptions.set(hub.subscriptionId, {
      id: hub.subscriptionId,
      name: hub.name,
      type: 'hub'
    });
  }
});

// From spokes
topology.spokes.forEach(spoke => {
  if (!subscriptions.has(spoke.subscriptionId)) {
    subscriptions.set(spoke.subscriptionId, {
      id: spoke.subscriptionId,
      name: spoke.name,
      type: 'spoke'
    });
  }
});

// If needed, get an array of unique subscription objects
const uniqueSubscriptions = Array.from(subscriptions.values());
```

### Generate Provider Aliases

**For each unique subscription:**

```hcl
provider "azurerm" {
  alias           = "hub-eastus"
  subscription_id = "aaaa-bbbb-cccc-dddd"
  
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
  subscription_id = "ffff-gggg-hhhh-iiii"
  
  features {}
}
```

### Apply Provider to Resources

```hcl
# In hub main.tf
resource "azurerm_resource_group" "hub" {
  provider = azurerm.hub-eastus
  
  name     = "rg-hub-eastus-prod"
  location = "eastus"
  tags     = local.common_tags
}

# In spoke main.tf
resource "azurerm_resource_group" "spoke" {
  provider = azurerm.spoke-aks-prod
  
  name     = "rg-spoke-aks-prod"
  location = "eastus"
  tags     = local.common_tags
}
```

---

## Global Constraints Mapping

### Naming Conventions

**JSON Input:**
```json
"globalConstraints": {
  "namingConventions": {
    "prefix": "contoso",
    "environment": "prod",
    "pattern": "{prefix}-{resource}-{environment}-{region}-{instance}"
  }
}
```

→

```hcl
# locals.tf
locals {
  naming_prefix = var.naming_prefix
  environment   = var.environment
  location_code = var.location_code_map[var.location]
  
  # Apply naming pattern
  resource_group_name = "${local.naming_prefix}-rg-${local.environment}-${local.location_code}-001"
  vnet_name           = "${local.naming_prefix}-vnet-${local.environment}-${local.location_code}"
}
```

### Required Tags

**JSON Input:**
```json
"globalConstraints": {
  "requiredTags": {
    "Environment": "Production",
    "CostCenter": "IT-Infrastructure",
    "Owner": "Platform Team",
    "Project": "AKS Landing Zone"
  }
}
```

→

```hcl
# locals.tf
locals {
  common_tags = merge(
    var.global_required_tags,
    {
      ManagedBy = "Terraform"
      CreatedOn = timestamp()
    }
  )
}

# variables.tf
variable "global_required_tags" {
  type = map(string)
  default = {
    Environment = "Production"
    CostCenter  = "IT-Infrastructure"
    Owner       = "Platform Team"
    Project     = "AKS Landing Zone"
  }
}
```

### Compliance Standards

**JSON Input:**
```json
"globalConstraints": {
  "complianceStandards": ["PCI-DSS", "HIPAA"]
}
```

→ **Applied as:**
- Private cluster enforcement
- Encryption at host enabled
- Network policies enforced
- Audit logging enabled
- Defender for Cloud enabled

```hcl
# Compliance-driven configuration
variable "enable_encryption_at_host" {
  type    = bool
  default = true  # Required for PCI-DSS, HIPAA
}

variable "private_cluster_enabled" {
  type    = bool
  default = true  # Required for HIPAA
}

variable "enable_defender" {
  type    = bool
  default = true  # Required for compliance
}
```

---

## Resource Properties Mapping

### Common Resource Properties

**Storage Account Example:**

```json
{
  "type": "storageAccount",
  "name": "stprod001",
  "sku": "Standard_GRS",
  "properties": {
    "accountTier": "Standard",
    "accountReplicationType": "GRS",
    "enableHttpsTrafficOnly": true,
    "minimumTlsVersion": "TLS1_2",
    "allowBlobPublicAccess": false,
    "networkAcls": {
      "defaultAction": "Deny",
      "bypass": ["AzureServices"]
    }
  }
}
```

→

```hcl
module "storage_account" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "~> 0.2"
  
  name                = "stprod001"
  resource_group_name = azurerm_resource_group.spoke.name
  location            = var.location
  
  account_tier             = "Standard"
  account_replication_type = "GRS"
  
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"
  
  public_network_access_enabled = false
  
  network_rules = {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
  
  enable_telemetry = true
  tags             = local.common_tags
}
```

---

## AVM Module Standards

### Module Source Format

**Always use Terraform Registry format:**

```hcl
source = "Azure/avm-{type}-{service}/azurerm"
```

Examples:
- `Azure/avm-res-network-virtualnetwork/azurerm`
- `Azure/avm-res-containerservice-managedcluster/azurerm`
- `Azure/avm-res-storage-storageaccount/azurerm`

### Version Pinning

**Always pin versions with pessimistic constraint:**

```hcl
version = "~> 0.4"  # Allows 0.4.x but not 0.5.0
```

### Telemetry

**Always enable telemetry:**

```hcl
enable_telemetry = true
```

### Tags

**Always apply common tags:**

```hcl
tags = local.common_tags
```

---

## Output File Generation

### Hub Output File Pattern

**File Name:** `{hub-name}-outputs.json`

**Generation Method:**

In hub's `deploy.sh`:
```bash
terraform apply tfplan
terraform output -json > ${HUB_NAME}-outputs.json
```

**Example Output File:**

```json
{
  "hub_vnet_id": {
    "value": "/subscriptions/.../virtualNetworks/vnet-hub-eastus-prod"
  },
  "firewall_private_ip": {
    "value": "10.0.1.4"
  },
  "log_analytics_workspace_id": {
    "value": "/subscriptions/.../workspaces/law-hub-eastus-prod"
  },
  "private_dns_zone_ids": {
    "value": {
      "privatelink.azurecr.io": "/subscriptions/.../privateDnsZones/privatelink.azurecr.io"
    }
  }
}
```

### Spoke Consumption Pattern

**In spoke's `data-sources.tf`:**

```hcl
locals {
  hub_outputs = jsondecode(file("../hub-${var.hub_name}/${var.hub_name}-outputs.json"))
}

# Access values (note .value accessor for terraform output -json format)
# local.hub_outputs.firewall_private_ip.value
# local.hub_outputs.log_analytics_workspace_id.value
# local.hub_outputs.private_dns_zone_ids.value["privatelink.azurecr.io"]
```

---

## Variable and Output Conventions

### Variable Naming

**Use snake_case:**
```hcl
variable "resource_group_name" { }
variable "enable_firewall" { }
variable "hub_vnet_address_space" { }
```

### Required Variable Properties

```hcl
variable "example" {
  type        = string
  description = "Clear description of purpose and usage"
  default     = "value"  # Optional
  
  validation {
    condition     = can(regex("^pattern$", var.example))
    error_message = "Helpful error message"
  }
}
```

### Output Naming

**Use snake_case and descriptive names:**
```hcl
output "hub_vnet_id" {
  description = "Hub Virtual Network resource ID"
  value       = module.hub_vnet.resource_id
}
```

---

## Validation and Quality Checks

### Pre-Generation Validation

1. **JSON Schema Validation**:
   - All required sections present
   - Hub references valid (spoke.hubName matches hub.name)
   - Subscription IDs are valid GUIDs
   - Resource types are recognized

2. **Dependency Validation**:
   - Spokes reference hubs that exist
   - AKS clusters reference spokes that exist
   - Cross-subscription permissions documented

### Post-Generation Validation

1. **Terraform Format**:
   ```bash
   terraform fmt -recursive -check
   ```

2. **Terraform Validate**:
   ```bash
   terraform init -backend=false
   terraform validate
   ```

3. **AVM Compliance**:
   - All modules use `Azure/avm-*` sources
   - All versions pinned with `~>` syntax
   - All modules have `enable_telemetry = true`
   - All variables have descriptions
   - No hardcoded values

---

## Best Practices

### File Organization

1. **main.tf**: Resource definitions only
2. **variables.tf**: All input variables
3. **outputs.tf**: All outputs
4. **locals.tf**: Computed values and transformations
5. **data-sources.tf**: Data sources and hub output reads
6. **providers.tf**: Provider configurations with aliases
7. **terraform.tf**: Terraform and backend configuration

### Comments

**Add comments for:**
- Complex logic or conditionals
- Business rules or compliance requirements
- Cross-subscription resource references
- Non-obvious resource dependencies

**Example:**
```hcl
# Route all egress traffic through hub firewall
# Required for PCI-DSS compliance and centralized logging
resource "azurerm_route" "to_firewall" {
  # ...
}
```

### Resource Dependencies

**Use explicit dependencies when needed:**
```hcl
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  # ...
  
  depends_on = [
    azurerm_resource_group.spoke,
    module.spoke_vnet
  ]
}
```

---

## Error Handling

### Missing Hub Reference

**Error:** Spoke references hub that doesn't exist

**Solution:**
- Validate `spoke.hubName` against `topology.hubs[].name`
- Provide clear error message with available hub names
- Suggest correction

### Missing AKS Configuration

**Error:** AKS spoke but no matching cluster in aksDesign

**Solution:**
- Validate `aksDesign.clusters[].spokeName` matches spoke name
- Provide clear error message
- Suggest adding cluster configuration to aksDesign

### Invalid Subscription ID

**Error:** Subscription ID not in GUID format

**Solution:**
- Validate format: `^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`
- Provide clear error message with correct format
- Show example: `aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee`

### Unsupported Resource Type

**Error:** Resource type not recognized

**Solution:**
- List supported types: storageAccount, sqlDatabase, serviceBus, eventHub, containerRegistry, keyVault, aksCluster
- Suggest closest match or "other" spoke type
- Provide link to documentation

---

## Integration Points

This instruction file is referenced by:
- `.claude/skills/terraform/generate-from-json/SKILL.md` - Primary consumer
- `.github/prompts/terraform/infrastructure.prompt.md` - Code pattern templates
- `.github/instructions/azure-verified-modules-terraform.instructions.md` - AVM standards
- `.github/instructions/generate-modern-terraform-code-for-azure.instructions.md` - Terraform best practices
- `.github/docs/customer-config-schema.md` - JSON schema reference

---

## Notes

- This mapping supports Terraform only (Bicep mapping will be separate)
- Provider aliases use resource names (hub/spoke names) for clarity
- Hub outputs are file-based for simplicity (alternative: remote state)
- Default resources applied when spoke.resources[] is empty
- All Azure resources use AVM modules (no raw azurerm resources)
- Cross-subscription scenarios require Network Contributor RBAC
- Generated code follows Azure Verified Modules contribution guidelines
