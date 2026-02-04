# AKS Landing Zone Deployment Scenarios

This document outlines different deployment scenarios based on enterprise governance and team responsibility models, including practical steps to implement each scenario.

## Table of Contents

1. [Deployment Scenarios](#deployment-scenarios)
2. [Security Posture Variants](#security-posture-variants)
3. [Practical Implementation Workflow](#practical-implementation-workflow)
4. [Implementation Patterns](#implementation-pattern)
5. [Environment Configuration](#environment-specific-tfvars)
6. [Decision Matrix](#decision-matrix)

## Scenario 1: Full Application Team Autonomy

**Who:** Application team creates and manages all spoke resources.

**Platform Team Provides:**
- Hub infrastructure (deployed from hub prompt)
- Hub outputs (VNet ID, Firewall IP, DNS zones, Log Analytics)

**Application Team Creates:**
- Resource Group
- Virtual Network and Subnets
- VNet Peering
- Route Tables
- NSGs
- AKS Cluster
- ACR, Key Vault, Private Endpoints

**Terraform Variables:**
```hcl
create_resource_group   = true
create_virtual_network  = true
create_vnet_peering    = true
create_route_table     = true
```

**Use Case:** Small-to-medium enterprises, DevOps-mature teams, development environments.

### Variant 1A: Standard Security (Default)
Basic NSG rules, optional routing through firewall, permissive egress for development velocity.

**Additional Variables:**
```hcl
enable_egress_restriction = false
egress_security_level    = "standard"
```

### Variant 1B: Egress-Restricted Security
Application team manages infrastructure but with security-first configuration.

**Additional Variables:**
```hcl
enable_egress_restriction = true
egress_security_level    = "strict"
```

**Changes:**
- Force tunnel all traffic (0.0.0.0/0) through Azure Firewall
- Restrictive NSGs: Deny direct internet, allow only via Firewall
- Network Policy enabled (Calico)
- AKS `outbound_type = "userDefinedRouting"`

**Use Case:** Development/test with security controls, smaller organizations needing compliance.

---

## Scenario 2: Platform-Provided Networking (BYO VNet)

**Who:** Platform team provisions network infrastructure; application team deploys workloads.

**Platform Team Provides:**
- Hub infrastructure
- Spoke Resource Group
- Spoke Virtual Network with pre-configured subnets
- VNet Peering to hub
- Route Tables (traffic via Firewall)
- NSGs with baseline rules

**Application Team Creates:**
- AKS Cluster (into provided subnets)
- ACR, Key Vault, Private Endpoints
- Workload-specific NSG rules

**Terraform Variables:**
```hcl
create_resource_group        = false
create_virtual_network       = false
create_vnet_peering         = false
create_route_table          = false

existing_resource_group_name       = "rg-spoke-aks-prod"
existing_virtual_network_name      = "vnet-spoke-aks-prod"
existing_aks_system_subnet_name    = "snet-aks-system"
existing_aks_user_subnet_name      = "snet-aks-user"
existing_private_endpoint_subnet_name = "snet-private-endpoints"
```

**Use Case:** Large enterprises, strict network governance, regulated industries, shared VNet scenarios.

### Variant 2A: Standard Security
Platform team provides networking with basic security controls.

**Additional Variables:**
```hcl
enable_egress_restriction = false
egress_security_level    = "standard"
```

### Variant 2B: Egress-Restricted Security (⭐ RECOMMENDED FOR PRODUCTION)
Platform team enforces security at infrastructure layer, application team inherits locked-down configuration.

**Additional Variables:**
```hcl
enable_egress_restriction = true
egress_security_level    = "strict"
```

**Platform Team Pre-Configures:**
- Route tables with 0.0.0.0/0 → Azure Firewall (force tunnel)
- Restrictive baseline NSGs (deny direct internet)
- Azure Firewall with deny-by-default policies
- Network Policy enabled

**Application Team Benefits:**
- Automatically inherits security controls
- Cannot accidentally bypass egress restrictions
- Focus on workloads, not security infrastructure

**SecOps Benefits:**
- Centralized traffic inspection and logging
- Consistent security posture across all spokes
- Reduced risk of misconfiguration

**Use Case:** Regulated industries (finance, healthcare), security-conscious enterprises, zero-trust architectures.

---

## Scenario 3: Hybrid Model

**Who:** Mixed responsibilities based on organizational policies.

**Platform Team Provides:**
- Hub infrastructure
- Spoke Resource Group
- Spoke Virtual Network (but not subnets)

**Application Team Creates:**
- Subnets (within provided VNet address space)
- VNet Peering
- Route Tables
- NSGs
- AKS Cluster
- ACR, Key Vault, Private Endpoints

**Terraform Variables:**
```hcl
create_resource_group   = false
create_virtual_network  = false
create_subnets         = true
create_vnet_peering    = true
create_route_table     = true

existing_resource_group_name  = "rg-spoke-aks-prod"
existing_virtual_network_name = "vnet-spoke-aks-prod"
```

**Use Case:** Phased adoption, organizations transitioning governance models.

### Variant 3A: Standard Security
Hybrid model with flexible security configuration.

**Additional Variables:**
```hcl
enable_egress_restriction = false
egress_security_level    = "standard"
```

### Variant 3B: Egress-Restricted Security
Application team manages routing but must comply with security requirements.

**Additional Variables:**
```hcl
enable_egress_restriction = true
egress_security_level    = "strict"
```

**Application Team Responsibilities:**
- Configure route tables with force tunnel to Firewall
- Implement restrictive NSG rules
- Enable Network Policy

**Use Case:** Phased security adoption, teams building security expertise.

---

## Scenario 4: Security-First Model (Egress Restricted)

**Who:** Platform team enforces security at infrastructure layer; application team deploys workloads into pre-hardened environment.

**Recommended Combination:** Scenario 2 (Platform-Provided Networking) + Egress Restriction

**Rationale:** This is the **gold standard for production environments** in regulated industries. Platform team controls all security-critical infrastructure, application teams cannot bypass restrictions.

**Platform Team Provides:**
- Hub infrastructure with Azure Firewall
- Spoke Resource Group (locked RBAC)
- Spoke Virtual Network with security-hardened subnets
- VNet Peering to hub
- **Route Tables with force tunnel (0.0.0.0/0 → Firewall)**
- **Restrictive NSGs (deny internet outbound)**
- **Azure Firewall deny-by-default policies with explicit allow list**
- Network Policy enabled on AKS

**Application Team Creates:**
- AKS Cluster (inherits locked-down network)
- ACR, Key Vault with Private Endpoints
- Workloads (automatically egress-restricted)

**Terraform Variables:**
```hcl
# Resource Ownership (Scenario 2)
create_resource_group        = false
create_virtual_network       = false
create_vnet_peering         = false
create_route_table          = false

existing_resource_group_name       = "rg-spoke-aks-prod"
existing_virtual_network_name      = "vnet-spoke-aks-prod"
existing_aks_system_subnet_name    = "snet-aks-system"
existing_aks_user_subnet_name      = "snet-aks-user"
existing_private_endpoint_subnet_name = "snet-private-endpoints"

# Security Posture (Egress Restricted)
enable_egress_restriction = true
egress_security_level    = "strict"
```

**Security Controls:**

| Control Layer | Configuration |
|--------------|---------------|
| **Route Table** | 0.0.0.0/0 → Azure Firewall (force tunnel), no internet gateway |
| **NSG Rules** | Deny internet outbound, allow VirtualNetwork, allow specific Azure services |
| **Azure Firewall** | Default deny, explicit allow for AKS requirements + approved endpoints |
| **Network Policy** | Calico or Azure Network Policy (pod-level segmentation) |
| **AKS Outbound** | `userDefinedRouting` (all traffic via Firewall) |
| **Private Endpoints** | Mandatory for ACR, Key Vault (bypass firewall inspection) |

**Key Benefits:**
1. 🔒 **Enforced Security**: Application teams inherit security, cannot bypass
2. 🔍 **Full Visibility**: All egress traffic logged and inspected at Firewall
3. 🎯 **Centralized Control**: SecOps manages allow list, consistent across spokes
4. ✅ **Compliance Ready**: Meets requirements for PCI-DSS, HIPAA, SOC2, etc.
5. 🚫 **Zero Trust**: Default deny, explicit allow model

**Use Case:** Production environments, regulated industries (finance, healthcare, government), enterprises with strict security requirements, zero-trust architectures.

**Testing:** See [egress-restriction-demo.md](../demos/egress-restriction-demo.md) for hands-on validation procedures.

---

## Security Posture Variants

All scenarios (1-4) can be deployed with different security postures. The egress restriction configuration is **independent** of the resource ownership model.

### Standard Security (Default)
**Characteristics:**
- Basic NSG rules (allow broad outbound)
- Optional routing through Azure Firewall
- Permissive firewall rules (if configured)
- Direct internet egress via AKS Load Balancer
- Network Policy optional

**Variables:**
```hcl
enable_egress_restriction = false
egress_security_level    = "standard"
```

**Use Case:** Development, testing, non-production environments where agility is prioritized.

### Egress-Restricted Security (Strict)
**Characteristics:**
- Restrictive NSGs (deny direct internet)
- Mandatory routing through Azure Firewall (force tunnel)
- Deny-by-default firewall policies
- No direct internet egress
- Network Policy required (Calico or Azure)

**Variables:**
```hcl
enable_egress_restriction = true
egress_security_level    = "strict"
```

**Use Case:** Production, regulated environments, security-first organizations.

### Comparison Matrix

| Aspect | Standard | Egress-Restricted |
|--------|----------|-------------------|
| **NSG Outbound** | Allow Internet | Deny Internet, Allow Firewall |
| **Route Table** | Optional | **Mandatory** (0.0.0.0/0 → FW) |
| **Firewall Policy** | Permissive | **Deny-by-default** |
| **AKS Outbound Type** | `loadBalancer` | `userDefinedRouting` |
| **Network Policy** | Optional | **Required** |
| **Private Endpoints** | Recommended | **Highly Recommended** |
| **Internet Access** | Direct via LB | **Only via Firewall** |
| **Traffic Visibility** | Limited | **Full (all logged)** |
| **Compliance** | Basic | **High (audit trails)** |

### When to Use Each Security Posture

**Use Standard Security When:**
- ✅ Development/test environments
- ✅ Proof-of-concept deployments
- ✅ Non-regulated workloads
- ✅ Need fast iteration and troubleshooting
- ✅ Cost optimization (no firewall for dev)

**Use Egress-Restricted Security When:**
- ✅ Production environments
- ✅ Processing sensitive data (PII, PHI, PCI)
- ✅ Regulated industries (finance, healthcare, government)
- ✅ Zero-trust architecture requirements
- ✅ Need audit trails for compliance
- ✅ SecOps requires centralized egress control

---

## Practical Implementation Workflow

This section provides step-by-step instructions for implementing each scenario.

### Prerequisites for All Scenarios

1. **Azure Subscription** with appropriate permissions
2. **Azure Storage Account** for Terraform remote state
3. **Azure CLI** authenticated: `az login`
4. **Terraform** installed (v1.5+ recommended)
5. **Git repository** cloned: `git clone <repo-url>`

### Workflow for Scenario 1: Full Application Team Autonomy

**Step 1: Deploy Hub (Platform Team)**

```bash
cd /workspaces/aks-lz-ghcp

# Use the hub prompt with GitHub Copilot
# Open: .github/prompts/hub-landing-zone.prompt.md
# Ask Copilot: "Implement this hub landing zone prompt"

# After code generation, review and validate
cd hub
terraform init
terraform validate
terraform plan -out=hub.tfplan

# Apply after approval
terraform apply hub.tfplan

# Capture outputs
terraform output -json > hub-outputs.json
```

**Step 2: Deploy Spoke (Application Team)**

```bash
cd /workspaces/aks-lz-ghcp

# Use the spoke prompt with GitHub Copilot
# Open: .github/prompts/spoke-aks.prompt.md
# Ask Copilot: "Implement this spoke AKS prompt using Scenario 1 (full autonomy)"

cd spoke-aks

# Create dev.tfvars for Scenario 1
cat > environments/dev.tfvars <<EOF
# Scenario 1: Application team creates all resources
create_resource_group  = true
create_virtual_network = true
create_vnet_peering   = true
create_route_table    = true

# Hub references (from hub-outputs.json)
hub_virtual_network_id        = "/subscriptions/xxx/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub"
hub_firewall_private_ip       = "10.0.1.4"
log_analytics_workspace_id    = "/subscriptions/xxx/resourceGroups/rg-hub/providers/Microsoft.OperationalInsights/workspaces/law-hub"
private_dns_zone_ids = {
  acr    = "/subscriptions/xxx/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io"
  keyvault = "/subscriptions/xxx/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
}

# Resource naming
resource_group_name  = "rg-spoke-aks-dev"
location            = "eastus"
environment         = "dev"
EOF

# Initialize and deploy
terraform init
terraform validate
terraform plan -var-file=environments/dev.tfvars -out=spoke-dev.tfplan

# Apply after approval
terraform apply spoke-dev.tfplan
```

**Step 3: Verify Deployment**

```bash
# Connect to AKS
az aks get-credentials --resource-group rg-spoke-aks-dev --name aks-dev

# Test connectivity
kubectl get nodes
kubectl get pods -A

# Verify private endpoint connectivity
nslookup myacr.azurecr.io
# Should resolve to private IP (10.1.x.x range)
```

---

### Workflow for Scenario 2: Platform-Provided Networking

**Step 1: Deploy Hub (Platform Team)**

```bash
# Same as Scenario 1
cd /workspaces/aks-lz-ghcp/hub
terraform init
terraform plan -out=hub.tfplan
terraform apply hub.tfplan
terraform output -json > hub-outputs.json
```

**Step 2: Deploy Spoke Network Infrastructure (Platform Team)**

```bash
cd /workspaces/aks-lz-ghcp

# Platform team uses modified spoke prompt or separate network module
# Ask Copilot: "Create a spoke network module that provisions only:
# - Resource Group
# - Virtual Network with subnets (AKS system, user, private endpoints)
# - VNet peering to hub
# - Route tables
# - Baseline NSGs"

cd spoke-network
terraform init
terraform plan -out=spoke-network.tfplan
terraform apply spoke-network.tfplan

# Capture network outputs for application team
terraform output -json > spoke-network-outputs.json
```

**Step 3: Deploy AKS Workloads (Application Team)**

```bash
cd /workspaces/aks-lz-ghcp

# Use spoke prompt with Scenario 2 configuration
# Open: .github/prompts/spoke-aks.prompt.md
# Ask Copilot: "Implement spoke AKS using Scenario 2 (platform-provided networking)"

cd spoke-aks

# Create prod.tfvars for Scenario 2
cat > environments/prod.tfvars <<EOF
# Scenario 2: Use existing platform-provided resources
create_resource_group  = false
create_virtual_network = false
create_vnet_peering   = false
create_route_table    = false

# Existing resource references (from spoke-network-outputs.json)
existing_resource_group_name       = "rg-spoke-aks-prod"
existing_virtual_network_name      = "vnet-spoke-aks-prod"
existing_aks_system_subnet_name    = "snet-aks-system"
existing_aks_user_subnet_name      = "snet-aks-user"
existing_private_endpoint_subnet_name = "snet-private-endpoints"

# Hub references (from hub-outputs.json)
hub_virtual_network_id        = "/subscriptions/xxx/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub"
hub_firewall_private_ip       = "10.0.1.4"
log_analytics_workspace_id    = "/subscriptions/xxx/resourceGroups/rg-hub/providers/Microsoft.OperationalInsights/workspaces/law-hub"
private_dns_zone_ids = {
  acr    = "/subscriptions/xxx/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io"
  keyvault = "/subscriptions/xxx/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
}

# Workload configuration
environment = "prod"
location    = "eastus"
EOF

terraform init
terraform validate
terraform plan -var-file=environments/prod.tfvars -out=spoke-prod.tfplan
terraform apply spoke-prod.tfplan
```

**Step 4: Verify Deployment**

```bash
# Application team verifies their resources
az aks get-credentials --resource-group rg-spoke-aks-prod --name aks-prod
kubectl get nodes

# Platform team verifies network flows
az network vnet peering list --resource-group rg-hub --vnet-name vnet-hub
az network route-table show --resource-group rg-spoke-aks-prod --name rt-aks
```

---

### Workflow for Scenario 3: Hybrid Model

**Step 1: Deploy Hub (Platform Team)**

```bash
# Same as previous scenarios
cd /workspaces/aks-lz-ghcp/hub
terraform apply
```

**Step 2: Provision Base Resources (Platform Team)**

```bash
# Platform team creates RG and VNet only (no subnets)
cd /workspaces/aks-lz-ghcp

# Ask Copilot: "Create minimal spoke resources: RG and empty VNet with address space 10.1.0.0/16"

cd spoke-base
terraform init
terraform apply
terraform output -json > spoke-base-outputs.json
```

**Step 3: Deploy Full Spoke (Application Team)**

```bash
cd /workspaces/aks-lz-ghcp/spoke-aks

# Create hybrid.tfvars for Scenario 3
cat > environments/hybrid.tfvars <<EOF
# Scenario 3: Hybrid - use existing RG/VNet, create subnets and workloads
create_resource_group  = false
create_virtual_network = false
create_subnets        = true   # Application team creates subnets
create_vnet_peering   = true   # Application team configures peering
create_route_table    = true   # Application team manages routing

existing_resource_group_name  = "rg-spoke-aks-hybrid"
existing_virtual_network_name = "vnet-spoke-aks-hybrid"

# Hub references
hub_virtual_network_id = "/subscriptions/xxx/.../vnet-hub"
hub_firewall_private_ip = "10.0.1.4"
# ... other hub outputs

environment = "hybrid"
EOF

terraform init
terraform plan -var-file=environments/hybrid.tfvars
terraform apply
```

---

### Tips for Smooth Implementation

1. **Extract Hub Outputs Automatically**
   ```bash
   # After hub deployment
   cd hub
   terraform output -json > ../hub-outputs.json
   
   # Use jq to extract specific values
   HUB_VNET_ID=$(terraform output -raw virtual_network_id)
   HUB_FW_IP=$(terraform output -raw firewall_private_ip)
   ```

2. **Use Remote State for Output Sharing**
   ```hcl
   # In spoke-aks/main.tf
   data "terraform_remote_state" "hub" {
     backend = "azurerm"
     config = {
       storage_account_name = "tfstatestorage"
       container_name       = "tfstate"
       key                  = "hub.tfstate"
     }
   }
   
   locals {
     hub_vnet_id = data.terraform_remote_state.hub.outputs.virtual_network_id
     hub_fw_ip   = data.terraform_remote_state.hub.outputs.firewall_private_ip
   }
   ```

3. **Validate Prerequisites**
   ```bash
   # Before deploying spoke, verify hub resources exist
   az network vnet show --ids $HUB_VNET_ID
   az network firewall show --ids $HUB_FIREWALL_ID
   az monitor log-analytics workspace show --ids $LOG_ANALYTICS_ID
   ```

4. **Use Terraform Workspaces for Environments**
   ```bash
   # Instead of multiple tfvars, use workspaces
   terraform workspace new dev
   terraform workspace new prod
   terraform workspace select dev
   terraform apply -var-file=environments/dev.tfvars
   ```

5. **Automated Pipeline Example (GitHub Actions)**
   ```yaml
   # .github/workflows/deploy-spoke.yml
   name: Deploy Spoke AKS
   on: workflow_dispatch
   
   jobs:
     deploy:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v4
         
         - name: Get Hub Outputs
           run: |
             cd hub
             terraform init
             terraform output -json > hub-outputs.json
         
         - name: Deploy Spoke
           run: |
             cd spoke-aks
             terraform init
             terraform apply -var-file=environments/${{ github.event.inputs.environment }}.tfvars -auto-approve
   ```

---

## Implementation Pattern

### Step 1: Define Variables

```hcl
# variables.tf
variable "create_resource_group" {
  type        = bool
  default     = true
  description = "Create new resource group or use existing"
}

variable "existing_resource_group_name" {
  type        = string
  default     = null
  description = "Name of existing resource group (required if create_resource_group = false)"
  
  validation {
    condition     = var.create_resource_group || var.existing_resource_group_name != null
    error_message = "existing_resource_group_name must be provided when create_resource_group is false"
  }
}

variable "create_virtual_network" {
  type        = bool
  default     = true
  description = "Create new VNet or use existing"
}

variable "existing_virtual_network_name" {
  type        = string
  default     = null
  description = "Name of existing VNet (required if create_virtual_network = false)"
}
```

### Step 2: Conditional Resources

```hcl
# main.tf
resource "azurerm_resource_group" "spoke" {
  count    = var.create_resource_group ? 1 : 0
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

data "azurerm_resource_group" "spoke" {
  count = var.create_resource_group ? 0 : 1
  name  = var.existing_resource_group_name
}

module "virtual_network" {
  count  = var.create_virtual_network ? 1 : 0
  source = "Azure/avm-res-network-virtualnetwork/azurerm"
  # ... configuration
}

data "azurerm_virtual_network" "spoke" {
  count               = var.create_virtual_network ? 0 : 1
  name                = var.existing_virtual_network_name
  resource_group_name = local.resource_group_name
}
```

### Step 3: Unified Locals

```hcl
# locals.tf
locals {
  # Unify references regardless of create vs. data source
  resource_group_name = var.create_resource_group ? azurerm_resource_group.spoke[0].name : data.azurerm_resource_group.spoke[0].name
  resource_group_id   = var.create_resource_group ? azurerm_resource_group.spoke[0].id : data.azurerm_resource_group.spoke[0].id
  
  virtual_network_id   = var.create_virtual_network ? module.virtual_network[0].resource_id : data.azurerm_virtual_network.spoke[0].id
  virtual_network_name = var.create_virtual_network ? module.virtual_network[0].name : data.azurerm_virtual_network.spoke[0].name
  
  aks_system_subnet_id = var.create_virtual_network ? module.virtual_network[0].subnets["aks-system"].id : data.azurerm_subnet.aks_system[0].id
}

# Now use locals throughout for consistent references
module "aks" {
  source = "Azure/avm-res-containerservice-managedcluster/azurerm"
  
  resource_group_name = local.resource_group_name
  vnet_subnet_id      = local.aks_system_subnet_id
  # ...
}
```

---

## Environment-Specific tfvars

### dev.tfvars (Application Team Autonomy)
```hcl
create_resource_group  = true
create_virtual_network = true
create_vnet_peering   = true
resource_group_name   = "rg-spoke-aks-dev"
```

### prod.tfvars (Platform-Provided)
```hcl
create_resource_group             = false
create_virtual_network            = false
create_vnet_peering              = false
existing_resource_group_name     = "rg-spoke-aks-prod"
existing_virtual_network_name    = "vnet-spoke-aks-prod"
existing_aks_system_subnet_name  = "snet-aks-system"
```

---

## Decision Matrix

| Resource | Scenario 1 | Scenario 2 | Scenario 3 | Notes |
|----------|-----------|-----------|-----------|-------|
| Resource Group | Create | Use Existing | Use Existing | Platform team typically manages |
| Virtual Network | Create | Use Existing | Use Existing | Platform team for network governance |
| Subnets | Create | Use Existing | Create | Can be delegated if VNet address space allows |
| VNet Peering | Create | Pre-Configured | Create | Platform team for network topology |
| Route Tables | Create | Pre-Configured | Create | Critical for egress control |
| NSGs | Create | Use Existing + Extend | Create | Platform team creates baseline; app team extends |
| AKS Cluster | Create | Create | Create | Always application team responsibility |
| ACR | Create | Create | Create | Always application team responsibility |
| Key Vault | Create | Create | Create | Always application team responsibility |

---

## Recommendations

1. **Start with Scenario 1** for initial PoC and development environments
2. **Transition to Scenario 2** for production with strict governance requirements
3. **Use validation blocks** to ensure required variables are provided based on conditional flags
4. **Document clearly** in README which scenario is being used
5. **Create separate tfvars** files per environment to handle different scenarios
6. **Test both paths** in CI/CD to ensure both create and use-existing paths work correctly
