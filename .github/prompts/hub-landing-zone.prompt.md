# Hub Landing Zone Deployment Prompt

Deploy a hub landing zone infrastructure on Azure using Azure Verified Modules (AVM) with the following requirements:

## Network Architecture

- Create a hub virtual network with appropriate address space (e.g., 10.0.0.0/16)
- Include the following subnets:
  - Azure Firewall subnet (/26)
  - Azure Bastion subnet (/26)
  - Gateway subnet for VPN/ExpressRoute (/27)
  - Management subnet for shared services (/24)

## Core Services

### Azure Firewall
- Deploy Azure Firewall in the hub VNet
- Configure firewall policies to support AKS egress requirements:
  - Allow HTTPS (443) for AKS control plane communication
  - Allow required AKS FQDN endpoints (mcr.microsoft.com, *.data.mcr.microsoft.com, management.azure.com, etc.)
  - Allow required Azure services (Azure Monitor, Container Registry, Key Vault)
  - Configure network and application rules for secure egress
- Capture diagnostic logs to Log Analytics

### Azure Bastion
- Deploy Azure Bastion for secure VM access
- Use Standard SKU for production, Basic SKU for dev/test
- Configure native client support if required

### Private DNS Zones
Create and link the following Azure Private DNS zones for AKS private endpoint connectivity:
- privatelink.azurecr.io (for Azure Container Registry)
- privatelink.vaultcore.azure.net (for Azure Key Vault)
- privatelink.blob.core.windows.net (for Azure Storage)
- privatelink.file.core.windows.net (for Azure Files)
- privatelink.monitor.azure.com (for Azure Monitor/Application Insights)
- privatelink.oms.opinsights.azure.com (for Log Analytics)
- privatelink.ods.opinsights.azure.com (for Log Analytics data collection)
- privatelink.agentsvc.azure-automation.net (for automation)

All DNS zones should be linked to the hub VNet with auto-registration disabled.

## Tier 1 Ingress (External Entry Point)

[DECISION REQUIRED] Select if public internet access is needed:

### Option A: Azure Front Door
- **Use Case**: Global multi-region deployments with CDN capabilities
- **Features**:
  - Global load balancing and CDN
  - WAF v2 with managed rule sets
  - DDoS protection (Microsoft backbone)
  - Private Link backend to App Gateway or AGFC
  - SSL/TLS termination at edge
  - URL-based routing and caching
- **Configuration**:
  - SKU: Premium (required for Private Link and WAF)
  - Frontend: Public HTTPS endpoint
  - Backend pools: Application Gateway or AGFC private IPs via Private Link
  - WAF Policy: OWASP CRS 3.2 + custom rules
- **AVM Module**: `Azure/avm-res-cdn-profile/azurerm` version `~> 0.3`
- **Cost Estimate**: ~$35/month base + data transfer (~$0.02-0.08/GB)

### Option B: Azure Application Gateway
- **Use Case**: Regional single-region deployments with direct AKS integration
- **Features**:
  - Regional L7 load balancer
  - Public or private frontend IP
  - WAF v2 enabled (OWASP CRS 3.2)
  - Direct integration with AKS (AGIC) or AGFC
  - SSL/TLS termination and end-to-end TLS
  - Path-based and host-based routing
  - Autoscaling support
- **Configuration**:
  - SKU: WAF_v2 (for production), Standard_v2 (for dev/test)
  - Frontend Type: Public or Private
  - Subnet: Dedicated /26 or larger in hub VNet
  - Backend Pool: AGFC private IP or AKS node IPs
  - Health Probes: HTTP/HTTPS to backend endpoints
  - WAF Policy: Prevention mode with OWASP CRS 3.2
- **AVM Module**: `Azure/avm-res-network-applicationgateway/azurerm` version `~> 0.4`
- **Network Requirements**:
  - Dedicated subnet: `AppGatewaySubnet` (minimum /26 CIDR)
  - NSG rules: Allow inbound 65200-65535 for health probes
  - UDR: Preserve internet route (0.0.0.0/0) for health probe responses
- **Cost Estimate**: ~$290/month base + data processing (~$0.008/GB)

### Option C: None (Internal-Only Access)
- **Use Case**: No public internet entry point required
- **Access Methods**:
  - ExpressRoute or VPN from on-premises
  - Azure internal services only (Private Endpoints)
  - Bastion for management access
- **Configuration**: No Tier 1 ingress deployed
- **Note**: Tier 2 ingress (in spoke) can still provide internal load balancing

### Configuration Variables Required

**If Azure Front Door selected**:
```hcl
variable "deploy_front_door" {
  type        = bool
  default     = false
  description = "Deploy Azure Front Door Premium for global CDN and WAF"
}

variable "front_door_sku" {
  type        = string
  default     = "Premium_AzureFrontDoor"
  description = "Front Door SKU (Premium required for Private Link and WAF)"
}

variable "front_door_waf_enabled" {
  type        = bool
  default     = true
  description = "Enable WAF policy on Front Door"
}

variable "front_door_backend_private_link" {
  type        = bool
  default     = true
  description = "Use Private Link to backend services"
}
```

**If Application Gateway selected**:
```hcl
variable "deploy_application_gateway" {
  type        = bool
  default     = false
  description = "Deploy Azure Application Gateway in hub VNet"
}

variable "app_gateway_sku" {
  type        = string
  default     = "WAF_v2"
  description = "Application Gateway SKU (WAF_v2 for production, Standard_v2 for dev)"
  validation {
    condition     = contains(["Standard_v2", "WAF_v2"], var.app_gateway_sku)
    error_message = "SKU must be Standard_v2 or WAF_v2"
  }
}

variable "app_gateway_frontend_type" {
  type        = string
  default     = "public"
  description = "Frontend IP type (public or private)"
  validation {
    condition     = contains(["public", "private"], var.app_gateway_frontend_type)
    error_message = "Frontend type must be public or private"
  }
}

variable "app_gateway_waf_enabled" {
  type        = bool
  default     = true
  description = "Enable WAF on Application Gateway"
}

variable "app_gateway_subnet_address_prefix" {
  type        = list(string)
  default     = ["10.0.4.0/26"]
  description = "Address prefix for Application Gateway subnet (minimum /26)"
}

variable "app_gateway_capacity" {
  type = object({
    min = number
    max = number
  })
  default = {
    min = 2
    max = 10
  }
  description = "Autoscaling capacity for Application Gateway"
}
```

### Outputs Required

**If Application Gateway deployed**:
- `app_gateway_id` - Resource ID for Tier 2 backend pool integration
- `app_gateway_backend_address_pool_ids` - Backend pool IDs for spoke integration
- `app_gateway_frontend_public_ip` - Public IP address (if public frontend)
- `app_gateway_frontend_private_ip` - Private IP address (if private frontend)
- `app_gateway_subnet_id` - Subnet ID for reference

**If Front Door deployed**:
- `front_door_id` - Resource ID
- `front_door_frontend_endpoint_urls` - Public endpoint URLs
- `front_door_waf_policy_id` - WAF policy ID
- `front_door_profile_name` - Profile name for backend integration

### Hub VNet Updates for Tier 1 Ingress

**If Application Gateway is deployed**, add subnet to hub VNet module:

```hcl
subnets = {
  AzureFirewallSubnet = {
    address_prefixes = ["10.0.0.0/26"]
  }
  AzureBastionSubnet = {
    address_prefixes = ["10.0.1.0/26"]
  }
  GatewaySubnet = {
    address_prefixes = ["10.0.2.0/27"]
  }
  ManagementSubnet = {
    address_prefixes = ["10.0.3.0/24"]
  }
  AppGatewaySubnet = {
    address_prefixes = var.app_gateway_subnet_address_prefix
    delegation       = null
    network_security_group = {
      rules = [
        {
          name                       = "AllowGatewayManager"
          priority                   = 100
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_address_prefix      = "GatewayManager"
          source_port_range          = "*"
          destination_address_prefix = "*"
          destination_port_range     = "65200-65535"
        },
        {
          name                       = "AllowAzureLoadBalancer"
          priority                   = 110
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "*"
          source_address_prefix      = "AzureLoadBalancer"
          source_port_range          = "*"
          destination_address_prefix = "*"
          destination_port_range     = "*"
        },
        {
          name                       = "AllowHTTPS"
          priority                   = 120
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_address_prefix      = "Internet"
          source_port_range          = "*"
          destination_address_prefix = "*"
          destination_port_range     = "443"
        }
      ]
    }
  }
}
```

## Monitoring and Logging

- Deploy Log Analytics Workspace in the hub for centralized logging
- Configure diagnostic settings for all networking resources
- Enable Azure Monitor for network monitoring
- Capture VNet flow logs (NSG flow logs)

## Security

- Use Managed Identities for all services
- Enable Azure DDoS Protection (Standard for production, Basic for dev/test)
- Implement Network Security Groups (NSGs) on all subnets except AzureFirewallSubnet
- Enable Azure Policy for governance and compliance

## Outputs Required

Export the following outputs for spoke consumption:
- Hub VNet ID and name
- Hub VNet address space
- Azure Firewall private IP address
- Log Analytics Workspace ID
- Private DNS zone IDs (all zones)
- Subnet IDs for peering and routing

## Deployment Structure

- Create Terraform configuration in `/hub` folder
- Follow AVM best practices and use AVM modules where available
- Create environment-specific tfvars files for dev and prod
- Use remote state backend (Azure Storage Account)
- Pin all module versions
- Enable telemetry on all AVM modules

## Tags

Apply consistent tagging:
- Environment (dev/test/prod)
- Owner (Platform Team)
- CostCenter
- Project (AKS Landing Zone)
- ManagedBy (Terraform)
