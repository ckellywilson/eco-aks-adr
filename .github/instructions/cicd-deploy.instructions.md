---
description: 'CI/CD landing zone specification for self-hosted ACI-based ADO pipeline agents'
applyTo: 'infra/terraform/cicd/**/*.tf'
---

# CI/CD Landing Zone Specification

This document is the **authoritative specification** for the CI/CD landing zone deployment. All Terraform code under `infra/terraform/cicd/` MUST conform to this spec. Copilot agents MUST read this spec before generating or modifying CI/CD `*.tf` files.

---

## Guidance Philosophy

**This spec prescribes architecture and constraints, not implementation details.** When generating or modifying Terraform code, Copilot agents MUST consult the latest Microsoft documentation for:

- AVM CI/CD Agents module properties and versions → [AVM CI/CD Agents and Runners](https://registry.terraform.io/modules/Azure/avm-ptn-cicd-agents-and-runners/azurerm/latest) and [AVM Module Index](https://azure.github.io/Azure-Verified-Modules/)
- ACI networking constraints (delegation, UDR limitations) → [ACI virtual network scenarios](https://learn.microsoft.com/en-us/azure/container-instances/container-instances-virtual-network-concepts)
- NAT Gateway for ACI egress → [Azure NAT Gateway](https://learn.microsoft.com/en-us/azure/nat-gateway/nat-overview)
- Managed identity for ADO agents → [Azure DevOps Managed Identity authentication](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/service-principal-managed-identity)
- Azure Landing Zone platform separation → [Azure Landing Zone architecture](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/) and [Platform vs. application landing zones](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/design-area/platform-landing-zone)

Do NOT hardcode values that Microsoft may update (ACI container image tags, SKU options, API versions). Instead, use module-managed constructs (e.g., `use_default_container_image = true`) where available, and reference authoritative docs for the rest.

---

## Architecture Overview

### Separation of Duties — Why a Dedicated CI/CD Landing Zone?

The [Azure Cloud Adoption Framework (CAF)](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/) and [Azure Landing Zone (ALZ)](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/enterprise-scale/architecture) architecture prescribe a clear separation between **connectivity** (hub), **platform tooling** (CI/CD, monitoring, identity), and **application workloads** (spokes):

| Landing Zone | Responsibility | Examples |
|---|---|---|
| **Hub** | Connectivity only — networking, DNS, firewall, egress control | VNet, Firewall, DNS Resolver, Bastion |
| **CI/CD** | Platform tooling — build/deploy agents, image management | ACI agents, ACR, NAT Gateway |
| **Spoke** | Application workloads — compute, storage, app-specific infra | AKS, ACR (app), Key Vault |

**Why not put agents in the hub or spoke?**

- **Hub**: The hub owns shared connectivity infrastructure. Mixing build agents into the hub VNet violates the single-responsibility principle and creates blast radius concerns — a misbehaving build could affect DNS, firewall, or peering.
- **Spoke**: Putting agents in a spoke creates a circular dependency — the spoke pipeline needs agents to deploy, but agents would live inside the spoke being deployed. A dedicated CI/CD landing zone breaks this cycle.
- **Dedicated CI/CD VNet**: Follows CAF guidance for platform landing zones. The CI/CD VNet is hub-managed (peered, custom DNS), isolated from workload traffic, and independently scalable.

### Hub Dependency

The CI/CD deployment MUST run **after** the hub is fully deployed. The CI/CD landing zone reads hub outputs via `terraform_remote_state` to get:

| Hub Output | CI/CD Usage |
|---|---|
| `spoke_vnet_ids` | VNet ID (hub_managed mode, key: `cicd-agents`) |
| `spoke_resource_group_names` | RG name (hub_managed mode, key: `cicd-agents`) |
| `private_dns_zone_ids` | ACR private endpoint DNS (`privatelink.azurecr.io`) |
| `log_analytics_workspace_id` | ACI container logging and diagnostics |

```hcl
data "terraform_remote_state" "hub" {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-terraform-state-dev"
    storage_account_name = "<backend-storage-account>"
    container_name       = "terraform-state-prod"
    key                  = "hub/terraform.tfstate"
    use_azuread_auth     = true
  }
}

locals {
  hub_outputs    = data.terraform_remote_state.hub.outputs
  cicd_rg_name   = local.hub_outputs.spoke_resource_group_names["cicd-agents"]
  cicd_vnet_id   = local.hub_outputs.spoke_vnet_ids["cicd-agents"]
}
```

### Component Inventory

Use Azure Verified Modules (AVM) where available. Always check the [AVM Module Index](https://azure.github.io/Azure-Verified-Modules/) for the latest module versions and property names before generating code.

| Component | Purpose | Terraform Module / Resource |
|---|---|---|
| CI/CD RG + VNet | Infrastructure container (hub-created) | Consumed via `terraform_remote_state` |
| Subnets | ACI agents, ACR private endpoint | AVM `avm-res-network-virtualnetwork` (subnet-only mode) |
| ACI-Based ADO Agents | Self-hosted pipeline agents | AVM `avm-ptn-cicd-agents-and-runners` |
| CI/CD Agent UAMI | Agent authentication with ADO and platform KV | `azurerm_user_assigned_identity` |
| RBAC Assignment | Key Vault Secrets User on platform KV | `azurerm_role_assignment` |
| NAT Gateway | ACI outbound connectivity (UDR not supported) | Created by AVM module (`nat_gateway_creation_enabled`) |
| ACR (module-managed) | Agent container image registry with private endpoint | Created by AVM module (private endpoint wired to hub DNS zone) |

---

## Hub-Managed Consumption Pattern

### Resource Group & VNet

The CI/CD landing zone uses the same hub-managed pattern as the spoke. The hub creates:
- CI/CD resource group (`rg-cicd-eus2-prod`)
- CI/CD VNet (`vnet-cicd-prod-eus2`) with custom DNS pointing to hub DNS resolver inbound IP

The CI/CD deployment MUST NOT create its own RG or VNet. Instead, it references them via hub remote state using `var.spoke_key` (default: `cicd-agents`):

```hcl
# Hub prod.tfvars entry for CI/CD landing zone
spoke_vnets = {
  "cicd-agents" = {
    hub_managed         = true
    name                = "vnet-cicd-prod-eus2"
    resource_group_name = "rg-cicd-eus2-prod"
    address_space       = ["10.2.0.0/24"]
  }
}
```

### Subnet Provisioning

The hub creates the VNet but does **NOT** create CI/CD subnets. Subnets are application-specific and owned by the CI/CD deployment. The CI/CD module uses the AVM VNet module in subnet-only mode to add subnets to the hub-created VNet.

---

## CI/CD VNet Subnet Layout

### Address Space

- **CI/CD VNet CIDR**: `10.2.0.0/24` (set by hub in `spoke_vnets` variable)

### Subnet Layout

| Subnet Key | Name | CIDR | Purpose | Delegation |
|---|---|---|---|---|
| `aci_agents` | aci-agents | `10.2.0.0/27` | ACI container group instances | `Microsoft.ContainerInstance/containerGroups` |
| `aci_agents_acr` | aci-agents-acr | `10.2.0.32/29` | ACR private endpoint for agent images | None |

### Subnet Sizing Guidance

- **ACI agents subnet** (`/27` = 30 IPs): Each ACI container group consumes one IP. With the default 2 agents, this provides ample headroom for scaling. ACI subnet delegation is **mandatory** — the subnet cannot contain any other resource types.
- **ACR private endpoint subnet** (`/29` = 6 IPs): Private endpoint for the module-managed ACR. Only needs 1 IP for the PE + Azure reserved IPs.

**CRITICAL**: ACI delegated subnets have networking constraints. Consult [ACI virtual network scenarios](https://learn.microsoft.com/en-us/azure/container-instances/container-instances-virtual-network-concepts) for current delegation requirements and limitations.

### Subnet Configuration

```hcl
subnet_config = {
  aci_agents = {
    name             = "aci-agents"
    address_prefixes = [var.aci_agents_subnet_cidr]
    delegation = [
      {
        name = "Microsoft.ContainerInstance.containerGroups"
        service_delegation = {
          name    = "Microsoft.ContainerInstance/containerGroups"
          actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
        }
      }
    ]
  }
  aci_agents_acr = {
    name             = "aci-agents-acr"
    address_prefixes = [var.aci_agents_acr_subnet_cidr]
  }
}
```

---

## AVM CI/CD Agents Module Specification

The CI/CD landing zone uses the [AVM CI/CD Agents and Runners pattern module](https://registry.terraform.io/modules/Azure/avm-ptn-cicd-agents-and-runners/azurerm/latest) to deploy self-hosted ADO pipeline agents running on Azure Container Instances.

### Module Configuration

| Setting | Value | Rationale |
|---|---|---|
| Compute Type | `azure_container_instance` | Lightweight, serverless agents — no VM management overhead |
| VNet Creation | Disabled (`false`) | Uses hub-created CI/CD VNet |
| RG Creation | Disabled (`false`) | Uses hub-created CI/CD resource group |
| Private Networking | Enabled (`true`) | Agents run inside the CI/CD VNet, no public exposure |
| Container Image | Module default (`use_default_container_image = true`) | Microsoft-maintained image via ACR Tasks — auto-updated |
| Container CPU | `2` cores | Sufficient for Terraform plan/apply workloads |
| Container Memory | `4` GB | Sufficient for Terraform plan/apply workloads |
| Agent Count | Configurable (default `2`) | Parallelism for hub + spoke pipelines |
| NAT Gateway | Enabled (`nat_gateway_creation_enabled = true`) | Required for ACI outbound — see [NAT Gateway section](#nat-gateway) |
| Log Analytics | Disabled creation, uses hub workspace | Centralized monitoring via hub |

### Container Image Lifecycle

The AVM module manages the agent container image lifecycle automatically:

1. **ACR**: The module creates a Premium-tier ACR with private endpoint
2. **ACR Tasks**: The module creates an ACR Task that builds and maintains the agent image from Microsoft's base
3. **Auto-update**: ACR Tasks rebuild the image when the base image is updated, keeping agents patched

The operator does NOT need to manage container images manually. Setting `use_default_container_image = true` delegates this entirely to the module.

### ACR Private Endpoint

The module-managed ACR uses a private endpoint wired to the hub's `privatelink.azurecr.io` DNS zone:

```hcl
container_registry_private_dns_zone_creation_enabled = false
container_registry_dns_zone_id                       = local.hub_outputs.private_dns_zone_ids["privatelink.azurecr.io"]
container_registry_private_endpoint_subnet_id        = module.cicd_subnets.subnets["aci_agents_acr"].resource_id
```

**Key**: DNS zone creation is disabled because the hub already owns the `privatelink.azurecr.io` zone. The module only creates the private endpoint and registers the A record in the hub's zone.

### ADO Configuration

```hcl
version_control_system_type         = "azuredevops"
version_control_system_organization = var.ado_organization_url
version_control_system_pool_name    = var.ado_agent_pool_name
```

- **Organization URL**: Full ADO org URL (e.g., `https://dev.azure.com/myorg`)
- **Pool Name**: Must match the ADO agent pool created in the ADO organization (default: `aci-cicd-pool`)

### Authentication: UAMI (No PAT)

The module uses Managed Identity authentication — **no Personal Access Tokens (PATs)**:

```hcl
version_control_system_authentication_method    = "uami"
user_assigned_managed_identity_creation_enabled = false
user_assigned_managed_identity_id               = azurerm_user_assigned_identity.cicd_agents.id
user_assigned_managed_identity_client_id        = azurerm_user_assigned_identity.cicd_agents.client_id
user_assigned_managed_identity_principal_id     = azurerm_user_assigned_identity.cicd_agents.principal_id
```

**Why UAMI over PAT?**
- No secret rotation required — UAMI tokens are auto-refreshed by Azure
- No risk of PAT expiration breaking pipelines
- Follows zero-trust principles — identity-based auth, not shared secrets
- UAMI can be scoped to specific RBAC roles

**IMPORTANT**: The UAMI must be registered in the ADO organization **before** the ACI agents can authenticate. See [ADO Agent Pool Registration](#ado-agent-pool-registration).

---

## Managed Identity & RBAC Specification

### Identities

| Identity | Name Pattern | Purpose |
|---|---|---|
| CI/CD Agent UAMI | `uami-cicd-agents-{env}-{location_code}` | ACI agent ADO authentication, platform KV access |

### Required Role Assignments

| Principal | Scope | Role | Purpose |
|---|---|---|---|
| CI/CD Agent UAMI | Platform Key Vault | `Key Vault Secrets User` | Read SSH keys and platform secrets for deployments |

```hcl
resource "azurerm_role_assignment" "cicd_agents_kv_reader" {
  scope                = var.platform_key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.cicd_agents.principal_id
}
```

### Platform Key Vault

The CI/CD agents need read access to a platform Key Vault containing:
- SSH key pairs for jump box VMs (created by `setup-ado-pipeline.sh`)
- Platform-level secrets consumed by Terraform during spoke deployments

The `platform_key_vault_id` is passed as a pipeline variable (`PLATFORM_KV_ID`), not committed in tfvars.

---

## DNS Resolution

The CI/CD VNet uses the same DNS resolution architecture as all other hub-managed spokes. The hub sets custom DNS on the CI/CD VNet pointing to the hub DNS resolver inbound endpoint.

### Resolution Flow

```
ACI Container (CI/CD Agent)
  → CI/CD VNet custom DNS server
    → Hub DNS Resolver Inbound Endpoint (10.0.6.x)
      → Azure DNS (168.63.129.16) via hub VNet
        → Private DNS Zone (linked to hub VNet)
          → A record → Private IP of target resource
```

This enables ACI agents to resolve:
- **ACR private endpoint** (`privatelink.azurecr.io`) — for pulling agent container images
- **AKS API server** (`privatelink.{region}.azmk8s.io`) — when spoke pipelines run kubectl/helm commands
- **Key Vault private endpoints** (`privatelink.vaultcore.azure.net`) — for reading platform secrets

No Terraform-managed DNS zone links are required on the CI/CD VNet. Resolution works entirely through the hub DNS resolver chain.

Reference: [Azure DNS Private Resolver architecture](https://learn.microsoft.com/en-us/azure/dns/private-resolver-architecture)

---

## NAT Gateway

### Why NAT Gateway Instead of Azure Firewall Egress?

ACI delegated subnets **do not support User-Defined Routes (UDRs)**. This is an Azure platform constraint — route tables cannot be associated with subnets that have the `Microsoft.ContainerInstance/containerGroups` delegation.

Since the hub's egress architecture relies on UDRs to route traffic to Azure Firewall, ACI containers cannot use this path. Instead, the AVM module creates a NAT Gateway attached to the ACI agents subnet for outbound connectivity.

| Egress Method | Supported on ACI Delegated Subnet? | Used By |
|---|---|---|
| Azure Firewall (via UDR) | ❌ No — UDRs not supported | Spoke AKS nodes |
| NAT Gateway | ✅ Yes | CI/CD ACI agents |
| Default outbound | ⚠️ Unreliable — Azure is deprecating default outbound | — |

```hcl
# AVM module handles NAT Gateway creation and subnet association
nat_gateway_creation_enabled = true
```

**Security consideration**: Traffic from ACI agents exits through the NAT Gateway public IP, bypassing the hub firewall. This is acceptable because:
1. ACI agents only need outbound to ADO services (`dev.azure.com`, `vstoken.dev.azure.com`) and Azure APIs
2. The CI/CD VNet has no inbound exposure — ACI containers are not reachable from the internet
3. NSGs on the ACI subnet can restrict outbound destinations if needed

Consult [ACI virtual network scenarios](https://learn.microsoft.com/en-us/azure/container-instances/container-instances-virtual-network-concepts) for current ACI networking constraints.

---

## Naming Conventions

All resources follow the pattern: `{resource-type}-{purpose}-{environment}-{location_code}`

Consult [Azure naming conventions](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming) and [abbreviation recommendations](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations) for current best practices.

| Resource | Naming Pattern | Example |
|---|---|---|
| Resource Group | `rg-cicd-{location_code}-{env}` | `rg-cicd-eus2-prod` |
| VNet | `vnet-cicd-{env}-{location_code}` | `vnet-cicd-prod-eus2` |
| CI/CD Agent UAMI | `uami-cicd-agents-{env}-{location_code}` | `uami-cicd-agents-prod-eus2` |
| ACI Agents Subnet | `aci-agents` | `aci-agents` |
| ACR PE Subnet | `aci-agents-acr` | `aci-agents-acr` |

**Note**: The AVM CI/CD module creates additional resources (ACR, NAT Gateway, ACI container groups) with names derived from its internal `postfix` parameter (`cicd-{env}`). These names are module-managed and should not be overridden unless the module exposes explicit naming inputs.

---

## Deployment Order & Dependencies

### Three-Pipeline Architecture

The CI/CD landing zone sits between hub and spoke in the deployment order:

```
Phase 1: Hub deployment (hub pipeline — runs on MS-hosted agents)
  └─→ Hub RG, VNet, Firewall, Bastion, DNS Resolver, Log Analytics
  └─→ Private DNS Zones (linked to hub VNet)
  └─→ CI/CD RG + VNet (hub_managed, custom DNS → hub resolver)
  └─→ Spoke RG + VNet (hub_managed, custom DNS → hub resolver)
  └─→ Bidirectional VNet Peering (hub ↔ CI/CD, hub ↔ spoke)

Phase 2: CI/CD deployment (cicd pipeline — runs on MS-hosted agents)
  └─→ Read hub remote state
  └─→ Subnets (into hub-created CI/CD VNet)
  └─→ UAMI identity
  └─→ RBAC: Key Vault Secrets User on platform KV
  └─→ AVM CI/CD Agents module:
      └─→ ACR + private endpoint + ACR Tasks (image build)
      └─→ NAT Gateway (ACI egress)
      └─→ ACI container groups (ADO agents)
      └─→ Agent registration with ADO pool

Phase 3: Manual — Register UAMI in ADO organization
  └─→ Add UAMI as service connection or managed identity in ADO
  └─→ Verify agents appear online in ADO pool

Phase 4: Spoke deployment (spoke pipeline — runs on SELF-HOSTED agents)
  └─→ AKS cluster, ACR, Key Vault, etc. (see spoke spec)
```

### Bootstrap Sequence

The bootstrap creates a chicken-and-egg situation: self-hosted agents don't exist until Phase 2 completes. The solution:

| Phase | Pipeline | Runs On | Rationale |
|---|---|---|---|
| 1 — Hub | `hub-deploy` | **Microsoft-hosted agents** | No self-hosted agents exist yet |
| 2 — CI/CD | `cicd-deploy` | **Microsoft-hosted agents** | Self-hosted agents are being created |
| 3 — ADO Registration | Manual | — | Register UAMI in ADO org settings |
| 4 — Spoke | `spoke-deploy` | **Self-hosted ACI agents** | Agents now online; spoke needs private network access |

**Why the spoke uses self-hosted agents**: The spoke AKS cluster is private — its API server is only accessible from peered VNets. Microsoft-hosted agents cannot reach private endpoints. The CI/CD VNet is peered with the hub, which is peered with the spoke, enabling ACI agents to reach the AKS API server through the peered network.

### Dependency Graph

```
Hub (MS-hosted)
  ↓
CI/CD (MS-hosted) ──→ [Manual: Register UAMI in ADO]
  ↓
Spoke (self-hosted ACI agents)
```

---

## ADO Agent Pool Registration

### Manual Step: Register UAMI in ADO Organization

After the CI/CD Terraform deployment completes, the UAMI must be registered in the ADO organization for the ACI agents to authenticate. This is a **one-time manual step**.

#### Prerequisites

1. CI/CD Terraform deployment is complete
2. UAMI `client_id` is available from Terraform outputs

#### Steps

1. **Get the UAMI client ID** from Terraform output:
   ```bash
   cd infra/terraform/cicd
   terraform output agent_uami_client_id
   ```

2. **Register the UAMI in ADO**:
   - Navigate to **ADO Organization Settings → Users**
   - Add the UAMI by its client ID as a user with appropriate access level
   - Grant the identity permissions to the agent pool

   Consult [Use managed identities with Azure DevOps](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/service-principal-managed-identity) for the current registration process.

3. **Verify agent registration**:
   ```bash
   # After UAMI registration, ACI containers will auto-register with ADO
   # Check the agent pool in ADO:
   # Organization Settings → Agent Pools → aci-cicd-pool → Agents tab
   # Agents should appear as "Online"
   ```

**Note**: If agents show as "Offline" after UAMI registration, restart the ACI container groups:
```bash
az container restart \
  --resource-group <cicd-rg-name> \
  --name <container-group-name>
```

---

## Outputs

| Output | Description | Consumer |
|---|---|---|
| `resource_group_name` | CI/CD resource group name | Reference, troubleshooting |
| `cicd_vnet_id` | CI/CD VNet resource ID | Cross-reference, peering verification |
| `agent_pool_name` | ADO agent pool name | Spoke pipeline `pool` configuration |
| `agent_uami_id` | CI/CD agent UAMI resource ID | ADO service connection setup |
| `agent_uami_client_id` | CI/CD agent UAMI client ID | ADO UAMI registration (manual step) |
| `agent_uami_principal_id` | CI/CD agent UAMI principal ID | RBAC assignments, troubleshooting |

### Outputs Consumed by Spoke Pipeline

The spoke pipeline YAML references the agent pool name to run on self-hosted agents:

```yaml
# Spoke pipeline — runs on self-hosted ACI agents
pool: aci-cicd-pool  # Must match agent_pool_name output
```

---

## Pre-Flight Checklist

Before deploying CI/CD infrastructure:

1. **Verify hub is deployed** — `terraform_remote_state.hub` must return valid outputs
2. **Verify hub-created CI/CD RG + VNet exist** — check `spoke_vnet_ids["cicd-agents"]` and `spoke_resource_group_names["cicd-agents"]` outputs
3. **Verify Azure authentication** — `az account show` confirms correct subscription
4. **Verify ACR DNS zone exists in hub** — `private_dns_zone_ids` output must include `privatelink.azurecr.io`
5. **Verify backend storage access** — enable public network access if needed
6. **Verify ADO organization URL** — ensure `ado_organization_url` is correct in tfvars
7. **Verify platform Key Vault** — `platform_key_vault_id` must be a valid KV resource ID

---

## Validation After Deployment

```bash
# 1. Verify ACI containers are running
az container list \
  --resource-group <cicd-rg-name> \
  --query "[].{Name:name, State:instanceView.state}" -o table

# 2. Verify ACR private endpoint resolves
nslookup <acr-login-server>
# Should resolve to private IP via hub DNS resolver chain

# 3. Verify NAT Gateway is attached to ACI subnet
az network nat gateway list \
  --resource-group <cicd-rg-name> -o table

# 4. Verify agents in ADO (after UAMI registration)
# ADO Portal → Organization Settings → Agent Pools → aci-cicd-pool
# Agents should show as "Online"

# 5. Run a test pipeline on the self-hosted pool
# Create a minimal pipeline targeting pool: aci-cicd-pool
# Verify it executes successfully
```

---

## Future: Managed DevOps Pools (MDP) Migration

[Azure Managed DevOps Pools](https://learn.microsoft.com/en-us/azure/devops/managed-devops-pools/) is a Microsoft-managed service that provides self-hosted agent capabilities without the operational overhead of managing ACI containers, images, and scaling.

When MDP reaches General Availability and supports the required features (UAMI auth, VNet injection, private endpoint access), this CI/CD landing zone should be evaluated for migration. Benefits include:

- **No image management** — Microsoft fully manages agent images and patching
- **Auto-scaling** — Scales agent count based on pipeline queue demand
- **Reduced Terraform surface** — Replaces ACI + ACR + NAT Gateway + ACR Tasks with a single resource

**Migration checklist** (evaluate when MDP is GA):
1. Verify MDP supports VNet injection into existing hub-managed VNets
2. Verify MDP supports UAMI authentication with ADO
3. Verify MDP agents can reach private endpoints (AKS API server, ACR, KV)
4. Verify MDP supports custom DNS (hub resolver chain)
5. Consult the [AVM Module Index](https://azure.github.io/Azure-Verified-Modules/) for an MDP AVM module

---

## Related Documentation

- Hub spec: `.github/instructions/hub-deploy.instructions.md`
- Spoke spec: `.github/instructions/spoke-deploy.instructions.md`
- ADO pipeline spec: `.github/instructions/ado-pipeline-setup.instructions.md`
- Terraform deployment workflow: `.github/instructions/terraform-deploy.instructions.md`
- Terraform destroy workflow: `.github/instructions/terraform-destroy.instructions.md`
- AVM usage: `.github/instructions/azure-verified-modules-terraform.instructions.md`
- CI/CD Terraform code: `infra/terraform/cicd/`

## Reference Documentation

- [Azure Landing Zone architecture](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/)
- [Platform vs. application landing zones](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/design-area/platform-landing-zone)
- [AVM CI/CD Agents and Runners module](https://registry.terraform.io/modules/Azure/avm-ptn-cicd-agents-and-runners/azurerm/latest)
- [ACI virtual network scenarios](https://learn.microsoft.com/en-us/azure/container-instances/container-instances-virtual-network-concepts)
- [Azure NAT Gateway overview](https://learn.microsoft.com/en-us/azure/nat-gateway/nat-overview)
- [Azure DevOps Managed Identity authentication](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/service-principal-managed-identity)
- [Azure DNS Private Resolver architecture](https://learn.microsoft.com/en-us/azure/dns/private-resolver-architecture)
- [Azure Managed DevOps Pools](https://learn.microsoft.com/en-us/azure/devops/managed-devops-pools/)
