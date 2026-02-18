---
description: 'CI/CD landing zone specification for self-hosted Container App Job ADO pipeline agents'
applyTo: 'infra/terraform/cicd/**/*.tf'
---

# CI/CD Landing Zone Specification

This document is the **authoritative specification** for the CI/CD landing zone deployment. All Terraform code under `infra/terraform/cicd/` MUST conform to this spec. Copilot agents MUST read this spec before generating or modifying CI/CD `*.tf` files.

---

## Guidance Philosophy

**This spec prescribes architecture and constraints, not implementation details.** When generating or modifying Terraform code, Copilot agents MUST consult the latest Microsoft documentation for:

- AVM CI/CD Agents module properties and versions → [AVM CI/CD Agents and Runners](https://registry.terraform.io/modules/Azure/avm-ptn-cicd-agents-and-runners/azurerm/latest) and [AVM Module Index](https://azure.github.io/Azure-Verified-Modules/)
- Container App Environment networking constraints (delegation, subnet sizing) → [Container Apps networking](https://learn.microsoft.com/en-us/azure/container-apps/networking)
- NAT Gateway for Container App egress → [Azure NAT Gateway](https://learn.microsoft.com/en-us/azure/nat-gateway/nat-overview)
- Managed identity for ADO agents → [Azure DevOps Managed Identity authentication](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/service-principal-managed-identity)
- Azure Landing Zone platform separation → [Azure Landing Zone architecture](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/) and [Platform vs. application landing zones](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/design-area/platform-landing-zone)

Do NOT hardcode values that Microsoft may update (container image tags, SKU options, API versions). Instead, use module-managed constructs (e.g., `use_default_container_image = true`) where available, and reference authoritative docs for the rest.

---

## Architecture Overview

### Separation of Duties — Why a Dedicated CI/CD Landing Zone?

The [Azure Cloud Adoption Framework (CAF)](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/) and [Azure Landing Zone (ALZ)](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/enterprise-scale/architecture) architecture prescribe a clear separation between **connectivity** (hub), **platform tooling** (CI/CD, monitoring, identity), and **application workloads** (spokes):

| Landing Zone | Responsibility | Examples |
|---|---|---|
| **Hub** | Connectivity only — networking, DNS, firewall, egress control | VNet, Firewall, DNS Resolver, Bastion |
| **CI/CD** | Platform tooling — build/deploy agents, image management | Container App Job agents, ACR, NAT Gateway |
| **Spoke** | Application workloads — compute, storage, app-specific infra | AKS, ACR (app), Key Vault |

**Why not put agents in the hub or spoke?**

- **Hub**: The hub owns shared connectivity infrastructure. Mixing build agents into the hub VNet violates the single-responsibility principle and creates blast radius concerns — a misbehaving build could affect DNS, firewall, or peering.
- **Spoke**: Putting agents in a spoke creates a circular dependency — the spoke pipeline needs agents to deploy, but agents would live inside the spoke being deployed. A dedicated CI/CD landing zone breaks this cycle.
- **Dedicated CI/CD VNet**: Follows CAF guidance for platform landing zones. The CI/CD VNet is self-contained (own RG, VNet, peering), isolated from workload traffic, and independently scalable.

### CI/CD as Platform Automation Hub

The CI/CD landing zone is the **platform automation hub** — all pipelines requiring private network access run through these self-hosted agents. The agents serve three primary purposes:

1. **Terraform IaC for spoke infrastructure** — Agents read SSH keys and platform secrets from the platform Key Vault (private endpoint) during `terraform apply` for spoke deployments
2. **Kubernetes workload deployment** — Agents run `helm upgrade` and `kubectl apply` against the private AKS API server, which is only reachable from peered VNets
3. **Future pipeline workloads** — Any new pipeline requiring private network access (e.g., database migrations, secret rotation, compliance scans) can target the `aci-cicd-pool` without additional infrastructure

### Hub Dependency (REQUIRED)

The hub MUST be deployed before the CI/CD landing zone. The hub provides centralized private DNS zones (per [Azure CAF guidance](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/private-link-and-dns-integration-at-scale)), DNS resolver, and the VNet for peering.

**Deployment order**: Hub first → CI/CD second → Spoke third.

| Hub Output | CI/CD Usage |
|---|---|
| `hub_vnet_id` | Remote VNet ID for bidirectional peering |
| `hub_vnet_name` | Hub VNet name for hub-to-CI/CD peering resource |
| `dns_resolver_inbound_ip` | CI/CD VNet custom DNS server |
| `private_dns_zone_ids` | DNS zones for ACR, blob, vault private endpoints |
| `log_analytics_workspace_id` | Container App Job logging and diagnostics |

All hub variables are **required** — there are no bootstrap defaults. CI/CD does NOT create its own private DNS zones; all zones are centralized in the hub per CAF guidance.

### Component Inventory

Use Azure Verified Modules (AVM) where available. Always check the [AVM Module Index](https://azure.github.io/Azure-Verified-Modules/) for the latest module versions and property names before generating code.

| Component | Purpose | Terraform Module / Resource |
|---|---|---|
| CI/CD RG + VNet | Infrastructure container (self-created) | `azurerm_resource_group` + `azurerm_virtual_network` |
| VNet Peering | Bidirectional hub ↔ CI/CD | `azurerm_virtual_network_peering` |
| Subnets | Container App agents, ACR PE, State SA + KV PE | `azurerm_subnet` |
| Container App Job ADO Agents | Self-hosted pipeline agents with KEDA auto-scaling (0 to N) | AVM `avm-ptn-cicd-agents-and-runners` |
| CI/CD Agent UAMI | Agent authentication with ADO and platform KV | `azurerm_user_assigned_identity` |
| RBAC Assignment | Key Vault Secrets User on platform KV | `azurerm_role_assignment` |
| NAT Gateway | Container App outbound connectivity (self-managed) | `azurerm_nat_gateway` + `azurerm_nat_gateway_public_ip_association` + `azurerm_subnet_nat_gateway_association` |
| ACR (module-managed) | Agent container image registry with private endpoint | Created by AVM module (PE wired to hub DNS zone) |
| State Storage Account PE | Private endpoint to script-created state SA | `azurerm_private_endpoint` (SA created by `setup-ado-pipeline.sh`) |
| Platform KV Private Endpoint | Private access to platform Key Vault from CI/CD VNet | `azurerm_private_endpoint` |

---

## Self-Contained Resource Pattern

### Resource Group, VNet & Peering

Unlike the spoke (which is hub-managed), the CI/CD landing zone creates its **own** resource group, VNet, and bidirectional peering. This keeps CI/CD infrastructure self-contained — the hub does not need a `spoke_vnets` entry for CI/CD.

The CI/CD VNet custom DNS is always set to the hub DNS resolver inbound IP. All private DNS zones are centralized in the hub per [Azure CAF guidance](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/private-link-and-dns-integration-at-scale). The CI/CD landing zone does NOT create its own private DNS zones — it references hub-owned zones for all private endpoints.

```hcl
resource "azurerm_resource_group" "cicd" {
  name     = var.cicd_resource_group_name
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_virtual_network" "cicd" {
  name                = var.cicd_vnet_name
  resource_group_name = azurerm_resource_group.cicd.name
  location            = azurerm_resource_group.cicd.location
  address_space       = var.cicd_vnet_address_space
  dns_servers         = [var.hub_dns_resolver_ip]
  tags                = local.common_tags
}

resource "azurerm_virtual_network_peering" "cicd_to_hub" {
  name                      = "peer-cicd-to-hub"
  resource_group_name       = azurerm_resource_group.cicd.name
  virtual_network_name      = azurerm_virtual_network.cicd.name
  remote_virtual_network_id = var.hub_vnet_id
  allow_forwarded_traffic   = true
}

resource "azurerm_virtual_network_peering" "hub_to_cicd" {
  name                      = "peer-hub-to-cicd"
  resource_group_name       = local.hub_rg_name
  virtual_network_name      = local.hub_vnet_name
  remote_virtual_network_id = azurerm_virtual_network.cicd.id
  allow_forwarded_traffic   = true
}
```

**Note**: The CI/CD service principal needs `Network Contributor` on the hub VNet (or hub RG) to create the hub-to-CI/CD peering direction.

### Hub Firewall Source Addresses

The CI/CD VNet CIDR (`10.2.0.0/24`) must be included in the hub's `spoke_vnet_address_spaces` variable (not `spoke_vnets`) so that hub firewall rules include CI/CD agents as an allowed source address.

### Subnet Provisioning

The CI/CD deployment creates subnets into its own VNet using `azurerm_subnet` resources. Subnets are application-specific and owned entirely by the CI/CD deployment.

---

## CI/CD VNet Subnet Layout

### Address Space

- **CI/CD VNet CIDR**: `10.2.0.0/24` (configured in CI/CD `prod.tfvars`)

### Subnet Layout

| Subnet Key | Name | CIDR | Purpose | Delegation |
|---|---|---|---|---|
| `container_app` | container-app | `10.2.0.0/27` | Container App Environment for ADO agents | `Microsoft.App/environments` |
| `aci_agents_acr` | aci-agents-acr | `10.2.0.32/29` | ACR private endpoint for agent images | None |
| `private_endpoints` | private-endpoints | `10.2.0.48/28` | State SA + Platform KV private endpoints | None |

### Subnet Sizing Guidance

- **Container App subnet** (`/27` = 32 addresses, 27 usable after Azure reservation): Container App Environments require a **minimum /27 subnet** with `Microsoft.App/environments` delegation. KEDA-scaled Container App Jobs dynamically create execution instances within this subnet. The `/27` provides headroom for concurrent pipeline executions.
- **ACR private endpoint subnet** (`/29` = 8 addresses, 3 usable after Azure reservation): Private endpoint for the module-managed ACR. Only needs 1 IP for the PE + Azure reserved IPs.
- **Private endpoints subnet** (`/28` = 16 addresses, 11 usable after Azure reservation): Hosts private endpoints for the co-located state storage account and platform Key Vault. Each private endpoint consumes 1 IP.

**CRITICAL**: Container App Environment delegated subnets require `Microsoft.App/environments` delegation and a minimum size of `/27`. Consult [Container Apps networking](https://learn.microsoft.com/en-us/azure/container-apps/networking) for current delegation requirements and limitations.

### Subnet Configuration

```hcl
resource "azurerm_subnet" "container_app" {
  name                 = "container-app"
  resource_group_name  = azurerm_resource_group.cicd.name
  virtual_network_name = azurerm_virtual_network.cicd.name
  address_prefixes     = [var.container_app_subnet_cidr]

  delegation {
    name = "container-app-env"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
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
```

---

## AVM CI/CD Agents Module Specification

The CI/CD landing zone uses the [AVM CI/CD Agents and Runners pattern module](https://registry.terraform.io/modules/Azure/avm-ptn-cicd-agents-and-runners/azurerm/latest) to deploy self-hosted ADO pipeline agents running on Container App Jobs with KEDA auto-scaling.

### Module Configuration

| Setting | Value | Rationale |
|---|---|---|
| Compute Type | `azure_container_app` | Container App Jobs with KEDA — scales to zero when idle, scales up on pipeline demand |
| VNet Creation | Disabled (`false`) | Uses self-created CI/CD VNet |
| RG Creation | Disabled (`false`) | Uses self-created CI/CD resource group |
| Private Networking | Enabled (`true`) | Agents run inside the CI/CD VNet, no public exposure |
| Container Image | Module default (`use_default_container_image = true`) | Microsoft-maintained image via ACR Tasks — auto-updated |
| Max Execution Count | `10` | Maximum concurrent pipeline jobs |
| Min Execution Count | `0` | Scale to zero when no pipelines are queued |
| Polling Interval | `30` seconds | KEDA checks ADO queue every 30s for pending jobs |
| NAT Gateway | Disabled (`nat_gateway_creation_enabled = false`) | Self-managed NAT Gateway — see [NAT Gateway section](#nat-gateway) |
| Log Analytics | Disabled creation, uses hub workspace (when available) | Centralized monitoring via hub |
| PAT | `null` (`version_control_system_personal_access_token = null`) | UAMI auth — no PAT needed |

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
container_registry_dns_zone_id                       = var.hub_acr_dns_zone_id
container_registry_private_endpoint_subnet_id        = azurerm_subnet.aci_agents_acr.id
```

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
version_control_system_personal_access_token    = null  # No PAT needed with UAMI + Container App Jobs
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
- **UAMI auth with Container App Jobs works natively** — unlike ACI, which required PAT fallback

**IMPORTANT**: The UAMI must be registered in the ADO organization's `Project Collection Service Accounts` group **before** the Container App Job agents can authenticate. See [ADO Agent Pool Registration](#ado-agent-pool-registration).

---

## Managed Identity & RBAC Specification

### Identities

| Identity | Name Pattern | Purpose |
|---|---|---|
| CI/CD Agent UAMI | `uami-cicd-agents-{env}-{location_code}` | Container App Job ADO authentication, platform KV access |

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

The CI/CD VNet custom DNS points to the hub DNS resolver inbound endpoint. All private endpoint resolution works through the hub DNS chain — the CI/CD landing zone does NOT own any private DNS zones.

### Resolution Flow

```
Container App Job (CI/CD Agent)
  → CI/CD VNet custom DNS server
    → Hub DNS Resolver Inbound Endpoint (10.0.6.x)
      → Azure DNS (168.63.129.16) via hub VNet
        → Private DNS Zone (linked to hub VNet)
          → A record → Private IP of target resource
```

This enables Container App Job agents to resolve:
- **ACR private endpoint** (`privatelink.azurecr.io`) — for pulling agent container images
- **State storage account** (`privatelink.blob.core.windows.net`) — for Terraform state access
- **Platform Key Vault** (`privatelink.vaultcore.azure.net`) — for reading platform secrets
- **AKS API server** (`privatelink.{region}.azmk8s.io`) — when spoke pipelines run kubectl/helm commands

Reference: [Azure DNS Private Resolver architecture](https://learn.microsoft.com/en-us/azure/dns/private-resolver-architecture)

---

## NAT Gateway

### Why NAT Gateway Instead of Azure Firewall Egress?

Container App Environment delegated subnets **do not support User-Defined Routes (UDRs)** for egress control. This is an Azure platform constraint — route tables cannot be associated with subnets that have the `Microsoft.App/environments` delegation.

Since the hub's egress architecture relies on UDRs to route traffic to Azure Firewall, Container App Jobs cannot use this path. Instead, a NAT Gateway is attached to the Container App subnet for outbound connectivity.

| Egress Method | Supported on Container App Delegated Subnet? | Used By |
|---|---|---|
| Azure Firewall (via UDR) | ❌ No — UDRs not supported | Spoke AKS nodes |
| NAT Gateway | ✅ Yes | CI/CD Container App Job agents |
| Default outbound | ⚠️ Unreliable — Azure is deprecating default outbound | — |

### Self-Managed NAT Gateway

The NAT Gateway is **self-managed** (created by Terraform before the AVM module) rather than module-managed. This is because the AVM module does not expose the NAT Gateway resource ID as an output, making it impossible to associate the NAT Gateway with the Container App subnet after module creation.

```hcl
# Self-managed NAT Gateway — created before the AVM module
resource "azurerm_nat_gateway" "cicd" {
  name                = "natgw-cicd-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.cicd.name
  location            = azurerm_resource_group.cicd.location
  sku_name            = "Standard"
  tags                = local.common_tags
}

resource "azurerm_public_ip" "natgw" {
  name                = "pip-natgw-cicd-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.cicd.name
  location            = azurerm_resource_group.cicd.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

resource "azurerm_nat_gateway_public_ip_association" "cicd" {
  nat_gateway_id       = azurerm_nat_gateway.cicd.id
  public_ip_address_id = azurerm_public_ip.natgw.id
}

resource "azurerm_subnet_nat_gateway_association" "container_app" {
  subnet_id      = azurerm_subnet.container_app.id
  nat_gateway_id = azurerm_nat_gateway.cicd.id
}

# AVM module — NAT Gateway creation disabled
nat_gateway_creation_enabled = false
```

**Security consideration**: Traffic from Container App Job agents exits through the NAT Gateway public IP, bypassing the hub firewall. This is acceptable because:
1. Container App Job agents only need outbound to ADO services (`dev.azure.com`, `vstoken.dev.azure.com`) and Azure APIs
2. The CI/CD VNet has no inbound exposure — Container App Jobs are not reachable from the internet
3. NSGs on the Container App subnet can restrict outbound destinations if needed

Consult [Container Apps networking](https://learn.microsoft.com/en-us/azure/container-apps/networking) for current Container App Environment networking constraints.

---

## Naming Conventions

All resources follow the pattern: `{resource-type}-{purpose}-{environment}-{location_code}`

Consult [Azure naming conventions](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming) and [abbreviation recommendations](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations) for current best practices.

| Resource | Naming Pattern | Example |
|---|---|---|
| Resource Group | `rg-cicd-{location_code}-{env}` | `rg-cicd-eus2-prod` |
| VNet | `vnet-cicd-{env}-{location_code}` | `vnet-cicd-prod-eus2` |
| CI/CD Agent UAMI | `uami-cicd-agents-{env}-{location_code}` | `uami-cicd-agents-prod-eus2` |
| Container App Subnet | `container-app` | `container-app` |
| ACR PE Subnet | `aci-agents-acr` | `aci-agents-acr` |
| Private Endpoints Subnet | `private-endpoints` | `private-endpoints` |

**Note**: The AVM CI/CD module creates additional resources (ACR, Container App Jobs, Container App Environment) with names derived from its internal `postfix` parameter (`cicd-{env}`). These names are module-managed and should not be overridden unless the module exposes explicit naming inputs.

---

## Deployment Order & Dependencies

### Three-Pipeline Architecture

The hub deploys first on MS-hosted agents (public state SA), then CI/CD deploys to create self-hosted agents, and finally the spoke deploys on self-hosted agents (private state SA + private AKS API).

```
Phase 1: Hub deployment (hub pipeline — MS-hosted agents)
  └─→ Hub RG, VNet, Firewall, Bastion, DNS Resolver, Log Analytics
  └─→ ALL private DNS Zones (linked to hub VNet)
  └─→ Spoke RG + VNet (hub_managed, custom DNS → hub resolver)
  └─→ Bidirectional VNet Peering (hub ↔ spoke)

Phase 2: CI/CD deployment (cicd pipeline — MS-hosted agents, first run only)
  └─→ Create CI/CD RG + VNet (custom DNS → hub resolver)
  └─→ Bidirectional VNet Peering (CI/CD ↔ hub)
  └─→ Subnets (container-app, aci-agents-acr, private-endpoints)
  └─→ Self-managed NAT Gateway
  └─→ UAMI identity
  └─→ RBAC: Key Vault Secrets User on platform KV
  └─→ State SA PE + Platform KV PE (using hub DNS zones)
  └─→ AVM CI/CD Agents module:
      └─→ ACR + private endpoint + ACR Tasks (image build)
      └─→ Container App Environment + Container App Jobs (KEDA-scaled agents)
      └─→ Placeholder job auto-registers with ADO pool

Phase 3: Manual — Register UAMI in ADO organization
  └─→ Add UAMI to Project Collection Service Accounts group
  └─→ Verify placeholder agent appears in ADO pool (shows "Offline" when idle — expected)

Phase 4: Lock down CI/CD+spoke state SA
  └─→ Disable public access on state SA
  └─→ All subsequent CI/CD and spoke runs use self-hosted agents through private endpoint

Phase 5: Spoke deployment (spoke pipeline — self-hosted agents)
  └─→ AKS cluster, ACR, Key Vault, etc. (see spoke spec)
```

### Deployment Sequence

| Phase | Pipeline | Runs On | Rationale |
|---|---|---|---|
| 1 — Hub | `hub-deploy` | **MS-hosted agents** | Hub state SA is public; no private access needed |
| 2 — CI/CD (first run) | `cicd-deploy` | **MS-hosted agents** | Self-hosted agents are being created; state SA still public |
| 3 — ADO Registration | Manual | — | Register UAMI in `Project Collection Service Accounts` |
| 4 — Lock down state SA | Manual | — | Disable public access on CI/CD+spoke state SA |
| 5 — CI/CD (subsequent) | `cicd-deploy` | **Self-hosted agents** (`aci-cicd-pool`) | State SA now private |
| 6 — Spoke | `spoke-deploy` | **Self-hosted agents** (`aci-cicd-pool`) | Private state SA + private AKS API server |

**Why the spoke uses self-hosted agents**: The spoke AKS cluster is private — its API server is only accessible from peered VNets. The CI/CD+spoke state SA is private — only accessible via private endpoint. Microsoft-hosted agents cannot reach private endpoints. The CI/CD VNet is peered with the hub, which is peered with the spoke, enabling Container App Job agents to reach both the AKS API server and the state SA.

### Dependency Graph

```
Hub (MS-hosted) ──→ CI/CD (MS-hosted, first run) ──→ [Manual: Register UAMI + Lock down state SA]
                      ↓
                    Spoke (self-hosted)
```

---

## ADO Agent Pool Registration

### Register UAMI in ADO Organization

After the CI/CD Terraform deployment completes, the UAMI must be registered in the ADO organization for the Container App Job agents to authenticate. This is a **one-time setup step**.

#### Prerequisites

1. CI/CD Terraform deployment is complete
2. UAMI `client_id` is available from Terraform outputs

#### UAMI Registration — `Project Collection Service Accounts` Group

The UAMI must be added to the **`Project Collection Service Accounts`** group in ADO. This is required for Container App Job agents to authenticate via UAMI — pool-level admin access alone is insufficient.

**Option A: Automated via Terraform** (recommended)

Use the `azuredevops` Terraform provider to automate registration:

```hcl
resource "azuredevops_service_principal_entitlement" "cicd_agent" {
  origin    = "aad"
  origin_id = azurerm_user_assigned_identity.cicd_agents.client_id
}

data "azuredevops_group" "project_collection_service_accounts" {
  name = "Project Collection Service Accounts"
}

resource "azuredevops_group_membership" "cicd_agent" {
  group   = data.azuredevops_group.project_collection_service_accounts.descriptor
  members = [azuredevops_service_principal_entitlement.cicd_agent.descriptor]
}
```

**Option B: Manual via ADO Portal**

1. **Get the UAMI client ID** from Terraform output:
   ```bash
   cd infra/terraform/cicd
   terraform output agent_uami_client_id
   ```

2. **Add the UAMI to ADO**:
   - Navigate to **ADO Organization Settings → Users → Add users**
   - Add the UAMI by its client ID
   - Set access level to `Basic`

3. **Add UAMI to Project Collection Service Accounts**:
   - Navigate to **ADO Organization Settings → Permissions → Project Collection Service Accounts → Members → Add**
   - Add the UAMI identity

Consult [Use managed identities with Azure DevOps](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/service-principal-managed-identity) for the current registration process.

#### Agent Behavior with Container App Jobs

Container App Jobs use KEDA to auto-scale based on the ADO pipeline queue:

- **Placeholder job**: The module creates a placeholder Container App Job that auto-registers with the ADO agent pool. This agent shows as **"Offline"** in the ADO pool when no pipelines are queued — this is **expected behavior** (scale-to-zero).
- **Pipeline execution**: When a pipeline is queued targeting the `aci-cicd-pool`, KEDA detects the pending job and triggers a new Container App Job execution. The agent comes online, runs the pipeline, and terminates.
- **No always-on agents**: Unlike ACI (which ran 2 always-on containers), Container App Jobs scale to zero when idle — no compute cost when no pipelines are running.

#### Verification

```bash
# Check the agent pool in ADO:
# Organization Settings → Agent Pools → aci-cicd-pool → Agents tab
# A placeholder agent should appear (may show "Offline" when idle — expected)

# Run a test pipeline to verify KEDA scaling:
# Create a minimal pipeline targeting pool: name: 'aci-cicd-pool'
# The agent should come online, execute, and terminate
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
| `state_sa_pe_ip` | State storage account private endpoint IP | Troubleshooting DNS resolution |
| `platform_kv_pe_ip` | Platform Key Vault private endpoint IP | Troubleshooting DNS resolution |

### Outputs Consumed by Spoke Pipeline

The spoke pipeline YAML references the agent pool name to run on self-hosted agents:

```yaml
# All pipelines (hub, cicd, spoke) — runs on self-hosted Container App Job agents
pool:
  name: 'aci-cicd-pool'  # Name kept for backward compatibility
```

---

## Pre-Flight Checklist

Before deploying CI/CD infrastructure:

1. **Verify Azure authentication** — `az account show` confirms correct subscription
2. **Verify backend storage access** — enable public network access if needed
3. **Verify ADO organization URL** — ensure `ado_organization_url` is correct in tfvars
4. **Verify platform Key Vault** — `platform_key_vault_id` must be a valid KV resource ID
5. **Verify hub is deployed** — hub provides DNS zones, resolver, and VNet for peering
6. **Verify hub DNS zones exist** — `hub_blob_dns_zone_id`, `hub_vault_dns_zone_id`, `hub_acr_dns_zone_id` must be valid zone IDs

---

## Validation After Deployment

```bash
# 1. Verify Container App Environment is running
az containerapp env list \
  --resource-group <cicd-rg-name> \
  --query "[].{Name:name, State:properties.provisioningState}" -o table

# 2. Verify Container App Jobs exist
az containerapp job list \
  --resource-group <cicd-rg-name> \
  --query "[].{Name:name, Status:properties.provisioningState}" -o table

# 3. Verify ACR private endpoint resolves
nslookup <acr-login-server>
# Should resolve to private IP via DNS zone (hub or CI/CD-owned)

# 4. Verify NAT Gateway is attached to Container App subnet
az network nat gateway list \
  --resource-group <cicd-rg-name> -o table

# 5. Verify state storage account private endpoint
nslookup <state-sa-name>.blob.core.windows.net
# Should resolve to private IP

# 6. Verify agents in ADO (after UAMI registration)
# ADO Portal → Organization Settings → Agent Pools → aci-cicd-pool
# Placeholder agent should appear (may show "Offline" when idle — expected)

# 7. Run a test pipeline on the self-hosted pool
# Create a minimal pipeline targeting pool: name: 'aci-cicd-pool'
# KEDA should trigger a Container App Job execution
# Verify it executes successfully
```

---

## Future: Managed DevOps Pools (MDP) Migration

[Azure Managed DevOps Pools](https://learn.microsoft.com/en-us/azure/devops/managed-devops-pools/) is a Microsoft-managed service that provides self-hosted agent capabilities without the operational overhead of managing Container App Jobs, images, and scaling.

When MDP reaches General Availability and supports the required features (UAMI auth, VNet injection, private endpoint access), this CI/CD landing zone should be evaluated for migration. Benefits include:

- **No image management** — Microsoft fully manages agent images and patching
- **Auto-scaling** — Scales agent count based on pipeline queue demand
- **Reduced Terraform surface** — Replaces Container App Jobs + ACR + NAT Gateway + ACR Tasks with a single resource

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
- [Container Apps networking](https://learn.microsoft.com/en-us/azure/container-apps/networking)
- [Azure NAT Gateway overview](https://learn.microsoft.com/en-us/azure/nat-gateway/nat-overview)
- [Azure DevOps Managed Identity authentication](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/service-principal-managed-identity)
- [Azure DNS Private Resolver architecture](https://learn.microsoft.com/en-us/azure/dns/private-resolver-architecture)
- [Azure Managed DevOps Pools](https://learn.microsoft.com/en-us/azure/devops/managed-devops-pools/)
