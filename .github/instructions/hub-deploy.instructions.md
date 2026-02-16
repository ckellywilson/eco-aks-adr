# Hub Infrastructure Specification

This document is the **authoritative specification** for the hub infrastructure deployment. All Terraform code under `infra/terraform/hub/` MUST conform to this spec. Copilot agents MUST read this spec before generating or modifying hub `*.tf` files.

---

## Guidance Philosophy

**This spec prescribes architecture and constraints, not implementation details.** When generating or modifying Terraform code, Copilot agents MUST consult the latest Microsoft documentation for:

- Module property names and versions → [AVM Module Index](https://azure.github.io/Azure-Verified-Modules/) and [Terraform Registry](https://registry.terraform.io/namespaces/Azure)
- Azure service requirements (SKUs, subnet sizes, naming rules) → [Azure documentation](https://learn.microsoft.com/en-us/azure/)
- AKS networking and egress rules → [AKS documentation](https://learn.microsoft.com/en-us/azure/aks/)
- DNS resolver behavior and constraints → [Azure DNS Private Resolver](https://learn.microsoft.com/en-us/azure/dns/private-resolver-architecture)

Do NOT hardcode values that Microsoft may update (FQDN lists, required ports, SKU options, API versions). Instead, use Azure-managed constructs (FQDN tags, service tags) where available, and reference authoritative docs for the rest.

---

## Architecture Overview

The hub implements a centralized **hub-spoke network topology** following the [Azure Landing Zone architecture](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/). The hub provides shared networking, security, DNS resolution, and monitoring services consumed by all spoke workloads.

### Component Inventory

Use Azure Verified Modules (AVM) where available. Always check the [AVM Module Index](https://azure.github.io/Azure-Verified-Modules/) for the latest module versions and property names before generating code.

| Component | Purpose | Terraform Module / Resource |
|---|---|---|
| Hub Resource Group | Container for all hub resources | `azurerm_resource_group` |
| Hub VNet | Central network with segregated subnets | AVM `avm-res-network-virtualnetwork` |
| Azure Firewall + Policy | Centralized egress control, L7 filtering | AVM `avm-res-network-azurefirewall` + `azurerm_firewall_policy` |
| Azure Bastion | Secure RDP/SSH access to management VMs | AVM `avm-res-network-bastionhost` |
| Private DNS Resolver | Centralized DNS resolution for all VNets | `azurerm_private_dns_resolver` + endpoints |
| Log Analytics Workspace | Centralized monitoring and diagnostics | AVM `avm-res-operationalinsights-workspace` |
| Private DNS Zones | Private endpoint name resolution | AVM `avm-res-network-privatednszone` |
| Jump Box VM | Management access with pre-installed tooling | `azurerm_linux_virtual_machine` |
| VNet Peering | Bidirectional hub-spoke connectivity | `azurerm_virtual_network_peering` |
| Spoke Resource Group | Container for spoke resources (hub_managed only) | `azurerm_resource_group` |
| Spoke VNet | Spoke network with custom DNS to hub resolver (hub_managed only) | AVM `avm-res-network-virtualnetwork` |

### Spoke Resources Provisioned from Hub

The hub deployment supports **two spoke provisioning modes**, controlled by the `hub_managed` flag in `var.spoke_vnets`:

| Mode | `hub_managed` | Hub Creates | Use Case |
|---|---|---|---|
| **Centralized** | `true` | Spoke RG + VNet + Peering | Enterprise-controlled, dev teams deploy into pre-created RG/VNet |
| **Delegated** | `false` | Peering only | Dev teams create their own RG + VNet, hub peers to them |

#### Hub-Managed Spokes (`hub_managed = true`)

The hub creates:
1. **Spoke Resource Group** — named per convention (`rg-{spoke}-{location_code}-{env}`)
2. **Spoke VNet** — with custom DNS set to hub DNS resolver inbound IP (automatic)
3. **Bidirectional VNet Peering** — hub-to-spoke and spoke-to-hub

The spoke deployment then deploys AKS and app resources **into** the hub-created RG and VNet, reading them via remote state.

```hcl
# Hub-managed spoke: custom DNS automatically points to hub resolver
module "spoke_vnet" {
  for_each = local.hub_managed_spokes
  # ...
  dns_servers = {
    dns_servers = [azurerm_private_dns_resolver_inbound_endpoint.hub[0].ip_configurations[0].private_ip_address]
  }
}
```

#### Delegated Spokes (`hub_managed = false`)

The hub only creates bidirectional peering. The spoke RG and VNet must already exist. The spoke deployment is responsible for setting custom DNS to the hub resolver IP.

#### Variable Configuration

```hcl
spoke_vnets = {
  "spoke-aks-prod" = {
    hub_managed         = true                      # Hub creates RG + VNet
    name                = "vnet-aks-prod-eus2"
    resource_group_name = "rg-aks-eus2-prod"
    address_space       = ["10.1.0.0/16"]
  }
  "cicd-agents" = {
    hub_managed         = true                      # Hub creates RG + VNet
    name                = "vnet-cicd-prod-eus2"
    resource_group_name = "rg-cicd-eus2-prod"
    address_space       = ["10.2.0.0/24"]           # Small — just ACI agents
  }
  "spoke-data" = {
    hub_managed         = false                     # Already exists, hub only peers
    name                = "vnet-data-prod-eus2"
    resource_group_name = "rg-data-eus2-prod"
    address_space       = ["10.2.0.0/16"]
  }
}
```

---

## Hub VNet Specification

### Address Space

- **Hub VNet CIDR**: `10.0.0.0/16`

### Subnet Layout

| Subnet Key | Name | CIDR | Purpose | Delegation |
|---|---|---|---|---|
| `AzureFirewallSubnet` | AzureFirewallSubnet | `10.0.1.0/26` | Azure Firewall (name is mandatory) | None |
| `AzureBastionSubnet` | AzureBastionSubnet | `10.0.2.0/27` | Azure Bastion (name is mandatory) | None |
| `GatewaySubnet` | GatewaySubnet | `10.0.3.0/27` | Reserved for VPN/ExpressRoute gateway | None |
| `management` | management | `10.0.4.0/24` | Jump box VMs, management tools | None |
| `dns_resolver_inbound` | dns-resolver-inbound | `10.0.6.0/28` | DNS Resolver inbound endpoint | `Microsoft.Network/dnsResolvers` |
| `dns_resolver_outbound` | dns-resolver-outbound | `10.0.7.0/28` | DNS Resolver outbound endpoint | `Microsoft.Network/dnsResolvers` |

### Constraints

- `AzureFirewallSubnet`, `AzureBastionSubnet`, and `GatewaySubnet` names are **Azure-mandated** — do not rename. Consult [Azure VNet subnet requirements](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-network-manage-subnet) for current minimum sizes.
- DNS resolver subnets require dedicated subnets with `Microsoft.Network/dnsResolvers` delegation. Consult [DNS Private Resolver subnet requirements](https://learn.microsoft.com/en-us/azure/dns/dns-private-resolver-overview#subnet-restrictions) for current minimum size.
- DNS resolver subnets **must not** contain any other resources.
- `GatewaySubnet` is reserved — do not deploy resources or reuse this address space.

---

## Azure Firewall Specification

Consult latest [Azure Firewall documentation](https://learn.microsoft.com/en-us/azure/firewall/) for current SKU options, availability zone support, and policy configuration.

### Configuration

- **SKU**: `AZFW_VNet` with configurable tier (`Standard` default)
- **Public IP**: Static, Standard SKU
- **Policy**: Separate `azurerm_firewall_policy` resource
- **Availability Zones**: Configurable (empty list = no zones)
- **Conditional deployment**: Controlled by `var.deploy_firewall`

### Firewall Rules

**Ownership model: Split** (Azure CAF pattern)

- **Hub owns baseline rules** (priority range 100–499): Rules that ALL spokes need. Use Azure-managed constructs (FQDN tags, service tags) wherever possible so rules stay current automatically. Defined in the hub deployment.
- **Each spoke owns its own rule collection group** (priority range 500+): Spoke-specific application rules (e.g., custom FQDNs, app ports). These are defined in the spoke deployment, targeting the hub's `azurerm_firewall_policy` ID via hub outputs.

This split allows adding new spokes without redeploying the hub, while maintaining centralized baseline egress policy.

Source addresses for all rules MUST be restricted to known VNet ranges (hub + spoke CIDRs). Never use wildcards for source addresses.

```hcl
# Hub baseline rules (hub/main.tf)
allowed_source_addresses = concat(var.hub_vnet_address_space, var.spoke_vnet_address_spaces)

# Spoke-specific rules (spoke-aks-prod/main.tf) — targets hub's policy
resource "azurerm_firewall_policy_rule_collection_group" "spoke_app_rules" {
  firewall_policy_id = local.hub_outputs.firewall_policy_id
  priority           = 500  # Must be >= 500 to avoid hub baseline range
  # ...
}
```

#### Hub Baseline Rule Collections (Priority 100–499)

**CRITICAL: Do NOT hardcode FQDN lists.** Azure Firewall provides the `AzureKubernetesService` FQDN tag that is automatically maintained by Microsoft with the current required FQDNs for AKS egress. Always use this tag instead of manually enumerating FQDNs.

1. **AKS Application Rules** (priority 110): Use the `AzureKubernetesService` FQDN tag for all AKS egress dependencies — this tag is automatically maintained by Microsoft
2. **AKS Network Rules** (priority 120): Use [Azure service tags](https://learn.microsoft.com/en-us/azure/virtual-network/service-tags-overview) (e.g., `AzureCloud`) where applicable. Consult [AKS required network rules](https://learn.microsoft.com/en-us/azure/aks/outbound-rules-control-egress) for current requirements.

```hcl
# PREFERRED: Use FQDN tag — auto-updates with Microsoft's required FQDNs
application_rule_collection {
  name     = "aks-dependencies"
  priority = 110
  action   = "Allow"

  rule {
    name = "aks-fqdn-tag"
    protocols {
      type = "Https"
      port = 443
    }
    source_addresses      = local.allowed_source_addresses
    destination_fqdn_tags = ["AzureKubernetesService"]
  }
}
```

When generating or reviewing firewall rules, always consult the latest Microsoft documentation:
- [AKS outbound network and FQDN rules](https://learn.microsoft.com/en-us/azure/aks/outbound-rules-control-egress)
- [Limit egress traffic with Azure Firewall](https://learn.microsoft.com/en-us/azure/aks/limit-egress-traffic)
- [Azure Firewall FQDN tags](https://learn.microsoft.com/en-us/azure/firewall/fqdn-tags)
- [Azure service tags](https://learn.microsoft.com/en-us/azure/virtual-network/service-tags-overview)

Reference: [AKS required outbound network rules](https://learn.microsoft.com/en-us/azure/aks/outbound-rules-control-egress)

---

## Azure Bastion Specification

Consult latest [Azure Bastion documentation](https://learn.microsoft.com/en-us/azure/bastion/) for current SKU options and subnet requirements.

- **SKU**: Configurable (consult docs for current tier options and feature differences)
- **Public IP**: Static, Standard SKU
- **Subnet**: `AzureBastionSubnet` (Azure-mandated name)
- **Conditional deployment**: Controlled by `var.deploy_bastion`

---

## Log Analytics Workspace Specification

Consult latest [Log Analytics documentation](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/log-analytics-workspace-overview) for current SKU options and retention limits.

- **Retention**: Configurable via `var.log_retention_days`
- **SKU**: Configurable (consult docs for current pricing tiers)
- **Consumers**: Hub diagnostics, spoke AKS Container Insights, spoke diagnostic settings
- **Naming**: `law-hub-{environment}-{location_code}`

---

## Private DNS Zones Specification

### Required Zones

The hub MUST create private DNS zones for all Azure PaaS services used by spoke workloads. Consult the [Azure private endpoint DNS configuration](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns) for the authoritative, current list of zone names per service.

At minimum, for an AKS landing zone, the following zones are needed:

| Zone | Purpose |
|---|---|
| `privatelink.{region}.azmk8s.io` | AKS API server private endpoint |
| `privatelink.azurecr.io` | Azure Container Registry private endpoint |
| `privatelink.vaultcore.azure.net` | Azure Key Vault private endpoint |
| `privatelink.blob.core.windows.net` | Azure Blob Storage private endpoint |
| `privatelink.file.core.windows.net` | Azure File Storage private endpoint |
| `privatelink.queue.core.windows.net` | Azure Queue Storage private endpoint |
| `privatelink.table.core.windows.net` | Azure Table Storage private endpoint |
| `privatelink.monitor.azure.com` | Azure Monitor private endpoint |
| `privatelink.oms.opinsights.azure.com` | Log Analytics private endpoint |

**Note**: Add additional zones as new PaaS services with private endpoints are introduced to spokes. The zone names above are illustrative of the current deployment — always verify against the [private endpoint DNS reference](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns) before adding or modifying zones.

### VNet Linking Constraint

**CRITICAL**: Private DNS zones are linked to the **hub VNet only** in Terraform. Spoke VNets do NOT require Terraform-managed DNS zone links because they use custom DNS pointing to the hub's DNS resolver.

**Note**: The AKS resource provider will **automatically create** a VNet link from the spoke VNet to the `privatelink.{region}.azmk8s.io` zone at cluster create/start time. This link is created outside of Terraform (by the AKS RP acting through the control plane UAMI) and does not need to be managed here. See the spoke spec for full details.

```hcl
virtual_network_links = {
  hub_vnet = {
    vnetlinkname = "link-{zone}-hub"
    vnetid       = module.hub_vnet.resource_id
  }
  # Spoke VNet links are NOT created here — spokes resolve via DNS resolver.
  # Note: AKS auto-creates a spoke VNet link to the AKS DNS zone at runtime
  # (see spoke-deploy.instructions.md "Spoke VNet DNS Zone Linking" section).
}
```

This is the [centralized private DNS architecture](https://learn.microsoft.com/en-us/azure/dns/private-resolver-architecture) recommended by Microsoft.

### Spoke VNet DNS Zone Linking — AKS Auto-Creates

Spoke VNets do **not** need Terraform-managed links to private DNS zones. The spoke resolves all private endpoints through the hub DNS resolver chain:

```
Spoke resource → custom DNS (hub resolver IP) → hub resolver → Azure DNS → private DNS zone (hub VNet-linked) → A record
```

**However**, the AKS resource provider **automatically creates** a VNet link from the spoke VNet to the `privatelink.{region}.azmk8s.io` DNS zone during private cluster provisioning. This is AKS platform behavior — confirmed via both Terraform deployment and manual `az aks create` testing. The AKS RP acts through the **control plane UAMI** (verified via Azure Activity Log — the UAMI's `principalId` appears as the operation caller).

This auto-created link:
- **Cannot be prevented**: The required `Private DNS Zone Contributor` role grants `Microsoft.Network/privateDnsZones/*`, which includes both `A/write` and `virtualNetworkLinks/write`
- **Is re-created on cluster start**: If manually removed, AKS re-creates it on every start/restart
- **Is harmless**: DNS resolution works via the hub resolver chain regardless
- **Is not in Terraform state**: No drift risk — the AKS RP creates it outside of Terraform
- **Applies only to the AKS DNS zone**: ACR, Key Vault, and other private endpoint zones are not affected

Reference: [Hub and spoke with custom DNS for private AKS clusters](https://learn.microsoft.com/en-us/azure/aks/private-clusters#hub-and-spoke-with-custom-dns-for-private-aks-clusters)

Known issues: [Azure/AKS#4998](https://github.com/Azure/AKS/issues/4998), [Azure/AKS#4841](https://github.com/Azure/AKS/issues/4841)

See the spoke spec (`spoke-deploy.instructions.md`) for verification commands to confirm the VNet link creator via Activity Log.

---

## DNS Architecture Specification

This section defines the complete DNS resolution architecture for the hub-spoke topology. This is the **core architectural contract** — all networking and AKS decisions depend on this design.

### Design Principles

1. **Centralized DNS control**: All private DNS zones live in the hub resource group, linked to the hub VNet in Terraform
2. **No Terraform-managed spoke VNet-to-zone linking**: Spokes resolve private endpoints via the hub DNS resolver, not via direct zone links. However, the AKS RP auto-creates a spoke VNet link to the AKS DNS zone at runtime (see [Spoke VNet DNS Zone Linking](#spoke-vnet-dns-zone-linking--aks-auto-creates) above).
3. **VNet peering ≠ DNS zone linking**: Peering provides network connectivity; DNS resolution is handled separately via custom DNS settings
4. **BYOD (Bring Your Own DNS) pattern for AKS**: The AKS control plane UAMI writes A records and VNet links to the centralized private DNS zone

### Components

```
┌─────────────────────────────────────────────────────────────┐
│ Hub VNet (10.0.0.0/16)                                      │
│                                                             │
│  ┌──────────────────────┐   ┌────────────────────────────┐  │
│  │ Private DNS Resolver  │   │ Private DNS Zones           │  │
│  │  Inbound  (10.0.6.x) │   │  privatelink.*.azmk8s.io   │  │
│  │  Outbound (10.0.7.x) │   │  privatelink.azurecr.io    │  │
│  │  Forwarding Ruleset   │   │  privatelink.vaultcore...  │  │
│  └──────────────────────┘   │  (all zones VNet-linked     │  │
│                              │   to hub VNet only)         │  │
│                              └────────────────────────────┘  │
│                                                             │
│  ┌──────────────────────┐   ┌────────────────────────────┐  │
│  │ Azure Firewall        │   │ Log Analytics Workspace     │  │
│  └──────────────────────┘   └────────────────────────────┘  │
└──────────────┬──────────────────────────────────────────────┘
               │ VNet Peering (bidirectional)
┌──────────────┴──────────────────────────────────────────────┐
│ Spoke VNet (10.1.0.0/16)                                    │
│   Custom DNS: [hub DNS resolver inbound IP]                 │
│                                                             │
│  ┌──────────────────────┐                                   │
│  │ AKS Cluster           │                                   │
│  │  UAMI → "Private DNS  │                                   │
│  │  Zone Contributor" on  │                                   │
│  │  privatelink.*.azmk8s  │                                   │
│  └──────────────────────┘                                   │
└─────────────────────────────────────────────────────────────┘
```

### DNS Resolution Flow

When an AKS pod (or node) resolves a private endpoint FQDN:

```
1. AKS Pod/Node
   └─→ CoreDNS (cluster DNS at service CIDR IP, e.g. 172.16.0.10)
       └─→ Spoke VNet custom DNS server
           └─→ Hub DNS Resolver Inbound Endpoint (10.0.6.x)
               └─→ Azure DNS (168.63.129.16) via hub VNet
                   └─→ Private DNS Zone (linked to hub VNet)
                       └─→ A record → Private IP of target resource
```

**Why this works without spoke VNet-to-zone linking**:
- The hub DNS resolver's inbound endpoint lives in the hub VNet
- The hub VNet IS linked to all private DNS zones
- When the resolver receives a query, it resolves against Azure DNS (168.63.129.16) in the context of the hub VNet
- Azure DNS sees the hub VNet's zone links and returns the private endpoint IP
- The resolver forwards the answer back to the spoke

Reference: [Azure DNS Private Resolver architecture](https://learn.microsoft.com/en-us/azure/dns/private-resolver-architecture)

### DNS Resolver Configuration

#### Inbound Endpoint
- **Purpose**: Receives DNS queries from spoke VNets (via custom DNS setting)
- **Subnet**: `dns-resolver-inbound` (`10.0.6.0/28`)
- **IP allocation**: Dynamic (Azure assigns from subnet range)
- **Output**: IP address exported as `dns_resolver_inbound_ip` for spoke consumption

#### Outbound Endpoint
- **Purpose**: Forwards DNS queries to external resolvers (on-premises, corporate DNS)
- **Subnet**: `dns-resolver-outbound` (`10.0.7.0/28`)

#### Forwarding Ruleset
- **VNet Link**: MUST be linked to the hub VNet
- **Rules**: Conditional forwarding for on-premises domains (e.g., `corp.ecolab.com.`, `local.`)
- **No rule needed for Azure private DNS zones**: The resolver automatically resolves zones linked to its VNet without explicit forwarding rules. Azure does not allow forwarding to `168.63.129.16`.

Reference: [DNS Private Resolver endpoints and rulesets](https://learn.microsoft.com/en-us/azure/dns/private-resolver-endpoints-rulesets)

#### DNS Resolution Loop Prevention

**CONSTRAINT**: Do NOT link a DNS forwarding ruleset to a VNet where the ruleset contains a rule targeting the resolver's own inbound endpoint. This causes a DNS resolution loop.

Reference: [Private Resolver architecture — avoid loops](https://learn.microsoft.com/en-us/azure/dns/private-resolver-architecture)

### AKS BYOD Private DNS Zone Pattern

When deploying a private AKS cluster with BYOD DNS:

1. **Hub creates** the `privatelink.{region}.azmk8s.io` private DNS zone
2. **Hub links** the zone to the hub VNet only
3. **Spoke grants** the AKS control plane UAMI `Private DNS Zone Contributor` role on the zone
4. **AKS creates** an A record in the zone pointing to the API server private endpoint IP
5. **Spoke VNet** uses custom DNS pointing to hub DNS resolver inbound IP
6. **AKS nodes** resolve the API server FQDN through the DNS chain above

```hcl
# Spoke grants AKS UAMI permission to write A records to hub's DNS zone
resource "azurerm_role_assignment" "control_plane_to_private_dns_zone" {
  scope                = local.hub_outputs.private_dns_zone_ids["privatelink.{region}.azmk8s.io"]
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.aks_control_plane.principal_id
}
```

Reference: [Use a private DNS zone with AKS](https://learn.microsoft.com/en-us/azure/aks/private-clusters#configure-a-private-dns-zone)

### Spoke VNet Custom DNS Configuration

The spoke VNet MUST set custom DNS servers pointing to the hub DNS resolver inbound endpoint:

```hcl
dns_servers = {
  dns_servers = [local.hub_outputs.dns_resolver_inbound_ip]
}
```

This ensures all DNS queries from spoke resources (AKS nodes, pods, VMs) are forwarded to the hub resolver, which can resolve both private DNS zones and external domains.

---

## VNet Peering Specification

### Design

- **Bidirectional**: Hub-to-spoke AND spoke-to-hub peering created from the hub deployment
- **Optional**: Controlled by `var.spoke_vnets` map (empty = no peering)
- **Phased deployment**: Hub deploys first with `spoke_vnets = {}`, then peering added after spoke exists

### Peering Properties

| Property | Hub-to-Spoke | Spoke-to-Hub |
|---|---|---|
| `allow_virtual_network_access` | `true` | `true` |
| `allow_forwarded_traffic` | `true` | `true` |
| `allow_gateway_transit` | `false` | `false` |
| `use_remote_gateways` | `false` | `false` |

### Constraint

- Spoke VNets MUST exist before adding to `var.spoke_vnets` (data source will fail otherwise)
- Peering provides **network connectivity only** — it does NOT enable DNS zone resolution for the spoke. DNS resolution relies on the custom DNS → resolver chain described above.

---

## Jump Box VM Specification

Consult latest [Azure VM documentation](https://learn.microsoft.com/en-us/azure/virtual-machines/) for current VM sizes, OS image versions, and security best practices.

- **Conditional deployment**: Controlled by `var.deploy_jumpbox`
- **SKU**: Configurable (select appropriate size for management workload)
- **OS**: Latest Ubuntu LTS (Gen2) — consult [Canonical on Azure](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/endorsed-distros) for current LTS version
- **Identity**: SystemAssigned managed identity
- **Subnet**: `management`
- **Pre-installed tools**: Azure CLI, kubectl, Helm, k9s, jq, vim, curl, wget, git — install from official package repositories or verify checksums for binary downloads
- **Security**: All binary downloads MUST be checksum-verified. Never pipe remote scripts to bash.

---

## Naming Conventions

All resources follow the pattern: `{resource-type}-{workload}-{environment}-{location_code}`

Consult the [Azure naming conventions](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming) and [abbreviation recommendations](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations) for current best practices.

| Resource | Naming Pattern | Example |
|---|---|---|
| Resource Group | `rg-hub-{location_code}-{env}` | `rg-hub-eus2-prod` |
| VNet | `vnet-hub-{env}-{location_code}` | `vnet-hub-prod-eus2` |
| Firewall | `afw-hub-{env}-{location_code}` | `afw-hub-prod-eus2` |
| Firewall Policy | `afwpol-hub-{env}-{location_code}` | `afwpol-hub-prod-eus2` |
| Bastion | `bas-hub-{env}-{location_code}` | `bas-hub-prod-eus2` |
| Log Analytics | `law-hub-{env}-{location_code}` | `law-hub-prod-eus2` |
| DNS Resolver | `dnspr-hub-{env}-{location_code}` | `dnspr-hub-prod-eus2` |
| Public IP | `pip-{svc}-hub-{env}-{location_code}` | `pip-afw-hub-prod-eus2` |

---

## Deployment Order & Dependencies

### CRITICAL: Deploy hub BEFORE any spokes

```
Phase 1: Hub + hub-managed spokes
  └─→ Hub Resource Group
  └─→ Hub VNet + Subnets
  └─→ Azure Firewall + Policy + Rules
  └─→ Azure Bastion
  └─→ Private DNS Resolver + Endpoints + Ruleset
  └─→ Log Analytics Workspace
  └─→ Private DNS Zones (linked to hub VNet)
  └─→ Jump Box VM (optional)
  └─→ Spoke RG + VNet (hub_managed only, custom DNS → hub resolver IP)
  └─→ Bidirectional VNet Peering (hub_managed only)

Phase 2: Spoke application deployments (consume hub outputs)
  └─→ AKS cluster + RBAC + private endpoint (into hub-created or self-created RG/VNet)

Phase 3: Hub update (delegated spokes only)
  └─→ Update hub tfvars with delegated spoke_vnets (hub_managed = false)
  └─→ Reapply hub to create bidirectional peering to existing spoke VNets
```

### Hub Outputs Consumed by Spokes

| Output | Consumer | Purpose |
|---|---|---|
| `dns_resolver_inbound_ip` | Spoke VNet custom DNS | DNS resolution via hub |
| `private_dns_zone_ids` | AKS BYOD DNS, ACR/KV private endpoints | Zone resource IDs for RBAC and PE config |
| `log_analytics_workspace_id` | AKS Container Insights, diagnostics | Centralized monitoring |
| `firewall_private_ip` | Spoke route table UDR | Egress through hub firewall |
| `firewall_policy_id` | Spoke firewall rule collection groups | Spoke-specific egress rules (priority ≥ 500) |
| `hub_vnet_id` | Reference only | Hub VNet resource ID |
| `spoke_vnet_ids` | Spoke deployments (hub_managed) | VNet ID for AKS subnet references |
| `spoke_resource_group_names` | Spoke deployments (hub_managed) | RG name for deploying into |

---

## Pre-Flight Checklist

Before deploying hub infrastructure:

1. **Azure Authentication**
   ```bash
   az account show
   ```
   Confirm correct subscription and sufficient permissions (Contributor or Owner).

2. **Backend Storage Access**
   ```bash
   # Verify backend storage account is accessible
   grep -E "(storage_account_name|resource_group_name)" backend-prod.tfbackend
   
   # Enable public access if needed
   az storage account update \
     --name <storage-account-name> \
     --resource-group <resource-group-name> \
     --public-network-access Enabled
   ```

3. **Initialize & Validate**
   ```bash
   terraform init -backend-config=backend-prod.tfbackend
   terraform fmt -check
   terraform validate
   ```

4. **Review Plan**
   ```bash
   terraform plan -var-file="prod.tfvars" -out=tfplan
   # Review plan carefully before applying
   terraform apply tfplan
   ```

---

## Validation Criteria

After deployment, verify these conditions to confirm spec compliance:

### DNS Resolution
```bash
# 1. Verify DNS resolver inbound endpoint has an IP
terraform output dns_resolver_inbound_ip
# Expected: non-null IP in 10.0.6.0/28 range

# 2. Verify all private DNS zones are created
terraform output private_dns_zone_ids
# Expected: map with all 9 zones

# 3. Verify DNS zones are linked to hub VNet only
az network private-dns zone list --resource-group <hub-rg> \
  --query "[].{Zone:name, Links:numberOfVirtualNetworkLinks}" -o table
# Expected: each zone has exactly 1 link (hub VNet)
```

### Network
```bash
# 4. Verify firewall has private IP
terraform output firewall_private_ip
# Expected: non-null IP in 10.0.1.0/26 range

# 5. Verify VNet peering (after Phase 3)
az network vnet peering list --resource-group <hub-rg> --vnet-name <hub-vnet> -o table
# Expected: one peering per spoke, state=Connected
```

### Monitoring
```bash
# 6. Verify Log Analytics workspace
terraform output log_analytics_workspace_id
# Expected: valid resource ID
```

---

## Terraform Constraints

### Module Versions
- Use Azure Verified Modules where available — check [AVM Module Index](https://azure.github.io/Azure-Verified-Modules/) for latest versions
- Pin versions to specific releases for production stability
- Set `enable_telemetry = true` on all AVM modules

### Idempotency
- Never use `timestamp()` in locals or tags — breaks idempotency
- Use `for_each` with empty default maps for optional resources (e.g., spoke peering)

### Tags
All resources MUST include:
```hcl
tags = merge(var.tags, {
  CreatedBy   = "Terraform"
  Environment = var.environment
})
```

### State Management
- Backend: Azure Storage with Azure AD authentication (`use_azuread_auth = true`)
- State key: `hub/terraform.tfstate`
- State lock: Azure blob lease (automatic)

---

## Error Recovery Patterns

See `.github/instructions/terraform-deploy.instructions.md` for comprehensive error recovery. Hub-specific patterns:

### ContainerInsights Orphaned Resource
Log Analytics with ContainerInsights creates a `Microsoft.OperationsManagement/solutions` resource not tracked in Terraform state. This can block resource group deletion during destroy. Manual cleanup via Azure Portal or CLI may be required.

### AVM VNet Orphaned NSGs
The AVM VNet module auto-creates NSGs per subnet (e.g., `vnet-name-subnet-nsg-region`) not tracked in Terraform state. These can block resource group deletion on destroy. Manual cleanup may be required.

### DNS Zone Link Conflicts
If a spoke deployment creates a DNS zone VNet link and the hub also tries to manage the same link, Terraform will error. Ensure only one deployment owns each DNS zone link.

---

## Related Specifications

- **CI/CD Landing Zone**: `.github/instructions/cicd-deploy.instructions.md`
- **Spoke AKS Landing Zone**: `.github/instructions/spoke-deploy.instructions.md`
- **Terraform Destroy**: `.github/instructions/terraform-destroy.instructions.md`
- **Terraform Deploy**: `.github/instructions/terraform-deploy.instructions.md`
- **AVM Usage**: `.github/instructions/azure-verified-modules-terraform.instructions.md`
- **Hub Terraform Code**: `infra/terraform/hub/`
- **CI/CD Terraform Code**: `infra/terraform/cicd/`
- **Spoke Terraform Code**: `infra/terraform/spoke/`

## Reference Documentation

- [Azure Landing Zone architecture](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/)
- [Hub-spoke network topology](https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/hybrid-networking/hub-spoke)
- [Azure DNS Private Resolver architecture](https://learn.microsoft.com/en-us/azure/dns/private-resolver-architecture)
- [DNS Private Resolver endpoints and rulesets](https://learn.microsoft.com/en-us/azure/dns/private-resolver-endpoints-rulesets)
- [Private AKS clusters](https://learn.microsoft.com/en-us/azure/aks/private-clusters)
- [AKS required outbound network rules](https://learn.microsoft.com/en-us/azure/aks/outbound-rules-control-egress)
- [Azure/AKS#4841 — Private cluster spoke VNet DNS issue](https://github.com/Azure/AKS/issues/4841)
- [Azure/AKS#4998 — Private cluster should not auto-link DNS zones](https://github.com/Azure/AKS/issues/4998)
