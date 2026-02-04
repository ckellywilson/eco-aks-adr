# AKS Spoke Landing Zone Deployment Prompt

⚠️ **STOP - CONFIGURATION DECISIONS REQUIRED FIRST**

**Before asking Copilot to implement this prompt:**

1. **Complete:** `.github/docs/aks-configuration-decisions.md` (AKS network configuration decisions)
2. **Complete:** `.github/docs/deployment-scenarios.md` (Deployment model selection)
3. **Replace all `[DECISION REQUIRED]` placeholders** in the configuration section below
4. **Review:** `.github/examples/*.tfvars` for reference configurations

---

## Your Configuration Decisions (REQUIRED)

**Replace ALL placeholders before proceeding. Remove this section after completion.**

```hcl
# ============================================================================
# NETWORK PLUGIN CONFIGURATION
# ============================================================================
network_plugin      = "[DECISION REQUIRED: azure]"
network_plugin_mode = "[DECISION REQUIRED: overlay | null]"
pod_cidr            = "[DECISION REQUIRED: 192.168.0.0/16 if overlay, omit if standard CNI]"

# ============================================================================
# DATA PLANE & NETWORK POLICY
# ============================================================================
network_dataplane   = "[DECISION REQUIRED: cilium | null]"
network_policy      = "[DECISION REQUIRED: cilium | azure | calico | null]"

# ============================================================================
# OUTBOUND TYPE (EGRESS CONTROL)
# ============================================================================
outbound_type       = "[DECISION REQUIRED: userDefinedRouting | loadBalancer | managedNATGateway]"

# ============================================================================
# SECURITY POSTURE
# ============================================================================
enable_egress_restriction = [DECISION REQUIRED: true | false]
egress_security_level     = "[DECISION REQUIRED: strict | standard]"

# ============================================================================
# DEPLOYMENT MODEL (from deployment-scenarios.md)
# ============================================================================
# Scenario: [DECISION REQUIRED: 1 | 2 | 3 | 4][DECISION REQUIRED: A | B]
create_resource_group   = [DECISION REQUIRED: true | false]
create_virtual_network  = [DECISION REQUIRED: true | false]
create_vnet_peering     = [DECISION REQUIRED: true | false]
create_route_table      = [DECISION REQUIRED: true | false]
```

**Microsoft Recommended Production Configuration:**
- Network Plugin: `azure` with `overlay` mode
- Data Plane: `cilium`
- Network Policy: `cilium`
- Outbound Type: `userDefinedRouting` (for egress restriction)
- Security: Egress Restricted (Scenario 2B)

**Example Configurations:** See `.github/examples/prod-egress-restricted.tfvars`

---

Deploy an AKS spoke landing zone infrastructure on Azure using Azure Verified Modules (AVM) with the following requirements:

## Deployment Flexibility

This prompt supports multiple deployment models based on enterprise governance patterns:

### Model A: Application Team Creates All Spoke Resources (Default)
Application team creates Resource Group, VNet, subnets, and all spoke resources.

### Model B: Platform Team Pre-Provisions Infrastructure
Platform team creates Resource Group and/or VNet. Application team deploys workload resources into existing infrastructure.

### Security Posture: Egress Restriction Control
Independent of deployment model, configure egress security posture:
- **Standard Security (Default)**: Basic NSGs, optional route tables, permissive egress
- **Egress-Restricted Security**: Force-tunneled traffic via Azure Firewall, restrictive NSGs, deny-by-default firewall rules

**Implementation Pattern:**
- Use input variables to control resource creation: `create_resource_group`, `create_virtual_network`, `create_subnets`
- Use `enable_egress_restriction` to control security posture
- When set to `false`, use data sources to reference existing resources
- Accept resource IDs/names as inputs when using existing resources
- Use conditional expressions: `count = var.create_resource_group ? 1 : 0`

Example variable structure:
```hcl
variable "create_resource_group" {
  type        = bool
  default     = true
  description = "Create new resource group (true) or use existing (false)"
}

variable "existing_resource_group_name" {
  type        = string
  default     = null
  description = "Name of existing resource group (required if create_resource_group = false)"
}

variable "enable_egress_restriction" {
  type        = bool
  default     = false
  description = "Enable strict egress controls via Azure Firewall (force tunnel all traffic)"
}

variable "egress_security_level" {
  type        = string
  default     = "standard"
  description = "Security posture: 'standard' (basic NSGs, permissive) or 'strict' (force tunnel, deny-by-default)"
  validation {
    condition     = contains(["standard", "strict"], var.egress_security_level)
    error_message = "Must be 'standard' or 'strict'"
  }
}
```

## Prerequisites

This spoke depends on hub landing zone outputs:
- Hub VNet ID and name
- Hub VNet address space
- Azure Firewall private IP address
- Log Analytics Workspace ID
- Private DNS zone IDs (all zones)

These should be passed as input variables or retrieved via remote state/data sources.

## Resource Group

**Flexible Deployment:**
- If `create_resource_group = true`: Create new resource group
- If `create_resource_group = false`: Use data source to reference existing resource group provided by platform team

```hcl
# Example data source for existing resource group
data "azurerm_resource_group" "spoke" {
  count = var.create_resource_group ? 0 : 1
  name  = var.existing_resource_group_name
}
```

## Network Architecture

**Flexible Deployment:**
- If `create_virtual_network = true`: Create new spoke VNet and subnets
- If `create_virtual_network = false`: Use data sources to reference existing VNet/subnets provided by platform team

### Virtual Network Requirements
- Spoke virtual network with appropriate address space (e.g., 10.1.0.0/16)
- Do not overlap with hub address space
- Include the following subnets:
  - AKS system node pool subnet (/24) with NSG
  - AKS user node pool subnet (/23) with NSG
  - Private endpoints subnet (/27) with NSG
  - Application Gateway subnet (/27) with NSG (optional, for ingress)

```hcl
# Example data source for existing VNet
data "azurerm_virtual_network" "spoke" {
  count               = var.create_virtual_network ? 0 : 1
  name                = var.existing_virtual_network_name
  resource_group_name = local.resource_group_name
}

# Example data source for existing subnets
data "azurerm_subnet" "aks_system" {
  count                = var.create_virtual_network ? 0 : 1
  name                 = var.existing_aks_system_subnet_name
  virtual_network_name = data.azurerm_virtual_network.spoke[0].name
  resource_group_name  = local.resource_group_name
}
```

### VNet Peering
**Flexible Deployment:**
- If `create_vnet_peering = true`: Create VNet peering (typically when application team creates VNet)
- If `create_vnet_peering = false`: Assume platform team has already configured peering

When creating peering:
- Configure bidirectional VNet peering between hub and spoke
- Enable gateway transit on hub side
- Use remote gateways on spoke side
- Allow forwarded traffic

### User Defined Routes (UDR)
**Flexible Deployment:**
- If `create_route_table = true`: Create and associate route table
- If `create_route_table = false`: Assume platform team has already configured routing

**Security Posture Configuration:**
- If `enable_egress_restriction = true` or `egress_security_level = "strict"`:
  - **Mandatory**: Create route 0.0.0.0/0 → Azure Firewall (force tunnel)
  - Route all egress traffic through hub Azure Firewall
  - No direct internet access from AKS nodes
- If `enable_egress_restriction = false` (default):
  - Optional routing through Azure Firewall
  - Can allow direct internet egress via Azure Load Balancer

When creating route table:
- Create route table for AKS subnets
- If egress restriction enabled: Route all traffic (0.0.0.0/0) through Azure Firewall in hub
- Associate route table with AKS node pool subnets
- Preserve AKS required routes (do not override 168.63.129.16/32, 169.254.169.254/32)

```hcl
# Example: Conditional default route based on egress restriction
resource "azurerm_route" "default_route" {
  count                  = var.create_route_table && (var.enable_egress_restriction || var.egress_security_level == "strict") ? 1 : 0
  name                   = "default-via-firewall"
  route_table_name       = azurerm_route_table.spoke[0].name
  resource_group_name    = local.resource_group_name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.hub_firewall_private_ip
}
```

## Egress Restriction Configuration

When `enable_egress_restriction = true` or `egress_security_level = "strict"`, implement the following security controls:

### Network Security Requirements
1. **Force Tunnel All Traffic**: All egress must route through Azure Firewall (0.0.0.0/0 → Firewall)
2. **Restrictive NSGs**: Deny direct internet access, allow only Azure Firewall and required Azure services
3. **Network Policy**: Enable Calico or Azure Network Policy for pod-level controls
4. **AKS Outbound Type**: Set to `userDefinedRouting` to force traffic through Firewall

### Azure Firewall Configuration (Coordinate with Platform Team)
Platform team must configure Azure Firewall with:
- **Default Action**: Deny all
- **Application Rules**: Explicit allow list for required FQDNs
  - AKS required endpoints: `*.hcp.<region>.azmk8s.io`, `mcr.microsoft.com`, etc.
  - Azure services: ACR, Key Vault, Log Analytics, Storage
  - Any application-specific endpoints
- **Network Rules**: Allow required IPs for Azure services
- **Logging**: Enable all firewall logs for audit

### NSG Configuration for Egress Restriction
When egress restriction is enabled:
```hcl
# Deny direct internet, allow firewall
locals {
  egress_restricted_nsg_rules = var.enable_egress_restriction || var.egress_security_level == "strict" ? [
    {
      name                       = "AllowAzureFirewall"
      priority                   = 100
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = var.hub_firewall_private_ip
    },
    {
      name                       = "AllowAzureServices"
      priority                   = 110
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "AzureCloud"
    },
    {
      name                       = "DenyInternetOutbound"
      priority                   = 4096
      direction                  = "Outbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "Internet"
    }
  ] : []
}
```

### AKS Configuration for Egress Restriction
```hcl
module "aks" {
  source = "Azure/avm-res-containerservice-managedcluster/azurerm"
  
  # Force all egress through firewall
  outbound_type = var.enable_egress_restriction || var.egress_security_level == "strict" ? "userDefinedRouting" : "loadBalancer"
  
  # Enable network policy for pod-level controls
  network_plugin      = "azure"
  network_policy      = var.enable_egress_restriction || var.egress_security_level == "strict" ? "calico" : "azure"
  
  # Other configuration...
}
```

### Testing Egress Restriction
See [egress-restriction-demo.md](../demos/egress-restriction-demo.md) for comprehensive testing procedures.

## Azure Kubernetes Service (AKS)

### Cluster Configuration
- Deploy private AKS cluster (API server not publicly accessible)
- Use Azure CNI networking for network policy support
- Enable Azure CNI Overlay or Azure CNI with dynamic IP allocation
- Configure managed identity for cluster
- Enable workload identity and OIDC issuer
- Integrate with Log Analytics workspace from hub

### Node Pools
- System node pool: 3 nodes, Standard_D4s_v5 (or appropriate size)
- User node pool: 2-5 nodes with autoscaling enabled
- Use availability zones for high availability
- Enable Azure Linux or Ubuntu node images

### Add-ons and Features
- Enable Azure Monitor Container Insights
- Enable Azure Key Vault CSI driver
- Enable secret rotation
- Enable Image Cleaner
- Configure Azure Policy add-on
- Enable Azure RBAC for Kubernetes authorization
- Enable Defender for Containers

### Network Policies
- Enable Calico or Azure Network Policy
- Configure egress through Azure Firewall
- Restrict pod-to-pod communication as needed

## Tier 2: AKS Ingress Configuration

[DECISION REQUIRED] Select AKS ingress controller based on your requirements:

### Option A: Application Gateway for Containers (AGFC) - **Microsoft Recommended**
- **Use Case**: Modern container-native ingress with WAF support
- **Features**:
  - Container-native ingress controller
  - Integrated WAF policy support (OWASP CRS)
  - Private frontend in spoke VNet
  - HTTP/2, gRPC, WebSocket support
  - Automatic certificate management
  - Health probes and traffic splitting
  - Best performance with Azure CNI Overlay
- **Requirements**:
  - **CRITICAL**: Requires `networkPluginMode = "overlay"` (Azure CNI Overlay mode)
  - Dedicated subnet in spoke VNet (minimum /24)
  - ALB Controller deployed via Helm in AKS cluster
- **AVM Module**: `Azure/avm-res-serviceNetworking-applicationLoadBalancer/azurerm` version `~> 0.1`
- **Helm Chart**: `oci://mcr.microsoft.com/application-lb/charts/alb-controller` version `~> 1.0`
- **Configuration**:
  ```hcl
  variable "deploy_agfc" {
    type        = bool
    default     = false
    description = "Deploy Application Gateway for Containers (AGFC)"
  }
  
  variable "agfc_subnet_address_prefix" {
    type        = list(string)
    default     = ["10.1.4.0/24"]
    description = "Address prefix for AGFC subnet"
  }
  
  variable "agfc_waf_enabled" {
    type        = bool
    default     = true
    description = "Enable WAF policy on AGFC"
  }
  ```
- **Cost Estimate**: ~$440/month base + capacity units

### Option B: NGINX Ingress Controller - **Community Standard**
- **Use Case**: Flexible, widely adopted ingress with extensive customization
- **Features**:
  - Open-source, widely adopted
  - Runs inside AKS cluster (pods)
  - Custom annotations support
  - Rate limiting, circuit breaker patterns
  - ModSecurity WAF integration (optional)
  - Prometheus metrics built-in
- **Requirements**:
  - No special network plugin requirements
  - Internal load balancer annotation for private IP
  - Namespace creation (default: ingress-system)
- **Helm Chart**: `https://kubernetes.github.io/ingress-nginx` version `~> 4.10`
- **Configuration**:
  ```hcl
  variable "deploy_nginx_ingress" {
    type        = bool
    default     = false
    description = "Deploy NGINX Ingress Controller"
  }
  
  variable "nginx_ingress_namespace" {
    type        = string
    default     = "ingress-system"
    description = "Namespace for NGINX Ingress Controller"
  }
  
  variable "nginx_internal_lb" {
    type        = bool
    default     = true
    description = "Use internal load balancer (private IP)"
  }
  
  variable "nginx_replica_count" {
    type        = number
    default     = 3
    description = "Number of NGINX ingress controller replicas"
  }
  ```
- **Deployment via Helm**:
  ```hcl
  resource "helm_release" "nginx_ingress" {
    count      = var.deploy_nginx_ingress ? 1 : 0
    name       = "ingress-nginx"
    repository = "https://kubernetes.github.io/ingress-nginx"
    chart      = "ingress-nginx"
    version    = "4.10.1"
    namespace  = var.nginx_ingress_namespace
    
    set {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-internal"
      value = "true"
    }
    
    set {
      name  = "controller.replicaCount"
      value = var.nginx_replica_count
    }
    
    depends_on = [module.aks]
  }
  ```
- **Cost Estimate**: ~$0 (runs on AKS nodes) + Azure Load Balancer (~$20/month)

### Option C: Istio Service Mesh - **Advanced Traffic Management**
- **Use Case**: Microservices with service-to-service communication needs
- **Features**:
  - Full service mesh capabilities
  - mTLS between services automatically
  - Advanced traffic management (canary, blue/green)
  - Distributed tracing and observability
  - Circuit breaker, retry policies
  - Ingress gateway for external traffic
- **Requirements**:
  - **Recommended**: Cilium dataplane (`networkDataplane = "cilium"`) for compatibility
  - Linux node pools only (no Windows support)
  - Additional resource overhead for sidecar proxies
- **Helm Charts**: 
  - Base: `https://istio-release.storage.googleapis.com/charts` - `istio/base`
  - Istiod: `https://istio-release.storage.googleapis.com/charts` - `istio/istiod`
  - Ingress Gateway: `https://istio-release.storage.googleapis.com/charts` - `istio/gateway`
- **Configuration**:
  ```hcl
  variable "deploy_istio" {
    type        = bool
    default     = false
    description = "Deploy Istio service mesh"
  }
  
  variable "istio_namespace" {
    type        = string
    default     = "istio-system"
    description = "Namespace for Istio"
  }
  
  variable "istio_ingress_gateway" {
    type        = bool
    default     = true
    description = "Deploy Istio ingress gateway"
  }
  ```
- **Cost Estimate**: ~$0 (runs on AKS nodes) + increased node resource requirements

### Option D: Azure Application Gateway Ingress Controller (AGIC) - **Legacy**
- **Use Case**: Direct integration with existing hub Application Gateway
- **Features**:
  - AKS addon integration
  - Shares hub Application Gateway (Tier 1)
  - WAF protection via App Gateway
  - No separate load balancer needed
  - Good for single-tier architecture
- **Requirements**:
  - Hub Application Gateway must be deployed
  - RBAC permissions to App Gateway resource
  - Cross-subscription permissions if different subs
- **AKS Addon**: Enable via `ingress_application_gateway` block
- **Configuration**:
  ```hcl
  variable "deploy_agic" {
    type        = bool
    default     = false
    description = "Deploy AGIC (Application Gateway Ingress Controller)"
  }
  
  variable "app_gateway_id" {
    type        = string
    default     = null
    description = "Application Gateway resource ID (from hub)"
  }
  
  # In AKS cluster configuration
  ingress_application_gateway {
    gateway_id = var.app_gateway_id
  }
  ```
- **Note**: Can share same App Gateway with Tier 1 for cost optimization
- **Cost Estimate**: Included in App Gateway cost (~$290/month if dedicated)

### Option E: Kubernetes Service LoadBalancer - **Simple L4**
- **Use Case**: Simple L4 load balancing without ingress features
- **Features**:
  - Basic Azure Load Balancer
  - TCP/UDP port mapping
  - No HTTP routing or SSL termination
  - Simplest option for non-HTTP workloads
- **Requirements**:
  - No special network plugin requirements
  - Each service gets own public or private IP
- **Configuration**: Built-in, no additional deployment needed
- **Cost Estimate**: ~$20/month per Load Balancer instance

### Option F: None - **No Ingress Controller**
- **Use Case**: Cluster-internal workloads only, no external access
- **Configuration**: No ingress controller deployed
- **Cost**: $0

### Integration with Tier 1 Ingress

**If both Tier 1 (hub) and Tier 2 (spoke) are deployed**:

1. **App Gateway (Tier 1) → AGFC (Tier 2)**:
   - App Gateway backend pool points to AGFC frontend private IP
   - AGFC handles container-native routing
   - Dual WAF for defense-in-depth

2. **App Gateway (Tier 1) → NGINX (Tier 2)**:
   - App Gateway backend pool points to NGINX LoadBalancer IP
   - NGINX handles path-based routing within cluster

3. **App Gateway (Tier 1) → AGIC (Tier 2)**:
   - **OPTIMIZATION**: Use same App Gateway for both tiers
   - Saves cost by sharing single App Gateway instance
   - AGIC manages App Gateway backend pools automatically

4. **Front Door (Tier 1) → AGFC/NGINX (Tier 2)**:
   - Front Door uses Private Link to connect to App Gateway or directly to spoke
   - Then routes to AGFC or NGINX as Tier 2

### Validation Rules

**Pre-deployment validation**:
- ✅ If AGFC selected, ensure `networkPluginMode = "overlay"`
- ✅ If AGIC selected and Tier 1 is App Gateway, consider sharing same instance
- ✅ If Istio selected, ensure Cilium dataplane for compatibility
- ✅ If Service Mesh selected, ensure Windows node pools are not primary
- ⚠️ AGFC and AGIC cannot coexist in same cluster

### Helm Provider Configuration

**Required for NGINX, Istio deployments**:
```hcl
# providers.tf
provider "helm" {
  kubernetes {
    host                   = module.aks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.aks.cluster_ca_certificate)
    client_certificate     = base64decode(module.aks.client_certificate)
    client_key             = base64decode(module.aks.client_key)
  }
}

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}
```

### Outputs Required

```hcl
output "ingress_type" {
  value       = var.deploy_agfc ? "agfc" : var.deploy_nginx_ingress ? "nginx" : var.deploy_istio ? "istio" : var.deploy_agic ? "agic" : "none"
  description = "Type of ingress controller deployed"
}

output "agfc_id" {
  value       = var.deploy_agfc ? module.agfc[0].id : null
  description = "AGFC resource ID (if deployed)"
}

output "agfc_frontend_ip" {
  value       = var.deploy_agfc ? module.agfc[0].frontend_ip : null
  description = "AGFC private frontend IP address"
}

output "nginx_load_balancer_ip" {
  value       = var.deploy_nginx_ingress ? kubernetes_service.nginx_ingress[0].status[0].load_balancer[0].ingress[0].ip : null
  description = "NGINX ingress load balancer IP"
}

output "istio_ingress_gateway_ip" {
  value       = var.deploy_istio && var.istio_ingress_gateway ? kubernetes_service.istio_gateway[0].status[0].load_balancer[0].ingress[0].ip : null
  description = "Istio ingress gateway load balancer IP"
}
```

## Azure Container Registry (ACR)

- Deploy Azure Container Registry (Premium SKU for private endpoints)
- Enable private endpoint in the spoke private endpoints subnet
- Connect to existing privatelink.azurecr.io DNS zone from hub
- Enable Content Trust and vulnerability scanning
- Configure geo-replication for production (optional)
- Grant AKS cluster pull permissions using managed identity
- Enable diagnostic logs to Log Analytics workspace
- Configure retention policies and lifecycle management

## Azure Key Vault

- Deploy Azure Key Vault (Standard or Premium SKU)
- Enable private endpoint in the spoke private endpoints subnet
- Connect to existing privatelink.vaultcore.azure.net DNS zone from hub
- Enable RBAC authorization model (not access policies)
- Grant AKS workload identities appropriate permissions
- Enable soft delete and purge protection
- Configure diagnostic logs to Log Analytics workspace
- Store AKS secrets and certificates:
  - TLS certificates for ingress
  - Application secrets
  - Service principal credentials (if needed)

### Key Vault CSI Integration
- Configure Secrets Store CSI driver for AKS
- Enable auto-rotation of secrets
- Create SecretProviderClass examples for reference

## Private Endpoints

Create private endpoints for:
- AKS API server (automatic with private cluster)
- Azure Container Registry
- Azure Key Vault

All private endpoints should:
- Be deployed in the private endpoints subnet
- Use private DNS zones from hub (via VNet link or peering DNS resolution)
- Have NSG rules allowing traffic from AKS subnets

## Monitoring and Logging

- Send all diagnostic logs to hub Log Analytics workspace
- Enable Container Insights for AKS
- Configure Prometheus and Grafana integration (optional)
- Set up alerts for:
  - Node health
  - Pod failures
  - Container registry storage usage
  - Key Vault access patterns

## Security

- Use Managed Identities for all services
- Enable Azure AD integration for AKS
- Configure RBAC for cluster access
- Implement pod security standards/policies
- Enable secrets encryption at rest
- Configure network policies for pod-to-pod communication
- Enable Azure Firewall integration for egress filtering
- Configure NSGs with least privilege access

### Network Security Groups (NSGs)
- AKS subnet NSGs: Allow traffic to/from Azure Firewall, deny internet
- Private endpoint subnet NSG: Allow traffic from AKS subnets
- Follow AKS NSG requirements (do not block required ports)

## Outputs Required

Export the following outputs:
- AKS cluster ID and name
- AKS cluster FQDN
- AKS identity (kubelet identity, cluster identity)
- ACR login server and ID
- Key Vault URI and ID
- Spoke VNet ID and name
- Subnet IDs

## Deployment Structure

- Create Terraform configuration in `/spoke-aks` folder
- Follow AVM best practices and use AVM modules where available:
  - Use `avm-res-containerservice-managedcluster` for AKS
  - Use `avm-res-containerregistry-registry` for ACR
  - Use `avm-res-keyvault-vault` for Key Vault
  - Use `avm-res-network-virtualnetwork` for spoke VNet (when creating new)
- Create environment-specific tfvars files for dev and prod
- Use remote state backend (Azure Storage Account)
- Pin all module versions
- Enable telemetry on all AVM modules

### Conditional Resource Pattern

Implement flexible resource creation using locals to unify resource references:

```hcl
locals {
  resource_group_name = var.create_resource_group ? azurerm_resource_group.spoke[0].name : data.azurerm_resource_group.spoke[0].name
  
  virtual_network_id = var.create_virtual_network ? module.virtual_network[0].resource_id : data.azurerm_virtual_network.spoke[0].id
  
  aks_system_subnet_id = var.create_virtual_network ? module.virtual_network[0].subnets["aks-system"].id : data.azurerm_subnet.aks_system[0].id
}
```

This pattern allows the same downstream resource configurations to work regardless of whether resources are created or pre-existing.

## Integration with Hub

- Reference hub resources via input variables or data sources
- Do not create duplicate Private DNS zones (use hub zones)
- Ensure all egress traffic routes through hub Azure Firewall
- Use hub Log Analytics workspace for all logging

## Tags

Apply consistent tagging:
- Environment (dev/test/prod)
- Owner (Application Team)
- CostCenter
- Project (AKS Landing Zone)
- ManagedBy (Terraform)
- WorkloadType (AKS)
