# Spoke Infrastructure Specification

This document is the **authoritative specification** for the spoke AKS infrastructure deployment. All Terraform code under `infra/terraform/spoke/` MUST conform to this spec. Copilot agents MUST read this spec before generating or modifying spoke `*.tf` files.

---

## Guidance Philosophy

**This spec prescribes architecture and constraints, not implementation details.** When generating or modifying Terraform code, Copilot agents MUST consult the latest Microsoft documentation for:

- AKS module properties and versions → [AVM AKS Module](https://registry.terraform.io/modules/Azure/avm-res-containerservice-managedcluster/azurerm/latest) and [AVM Module Index](https://azure.github.io/Azure-Verified-Modules/)
- AKS networking, CNI Overlay, Cilium → [AKS networking concepts](https://learn.microsoft.com/en-us/azure/aks/concepts-network), [Azure CNI Overlay](https://learn.microsoft.com/en-us/azure/aks/concepts-network-azure-cni-overlay), [Azure CNI powered by Cilium](https://learn.microsoft.com/en-us/azure/aks/azure-cni-powered-by-cilium)
- AKS private cluster + BYOD DNS → [Private AKS clusters](https://learn.microsoft.com/en-us/azure/aks/private-clusters), [Configure a private DNS zone](https://learn.microsoft.com/en-us/azure/aks/private-clusters#configure-a-private-dns-zone)
- Private endpoint DNS zones → [Private endpoint DNS configuration](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns)
- Azure Firewall egress for AKS → [AKS outbound network rules](https://learn.microsoft.com/en-us/azure/aks/outbound-rules-control-egress), [Limit egress with Azure Firewall](https://learn.microsoft.com/en-us/azure/aks/limit-egress-traffic)
- RBAC for AKS managed identities → [AKS managed identities](https://learn.microsoft.com/en-us/azure/aks/use-managed-identity)

Do NOT hardcode values that Microsoft may update (FQDN lists, required ports, SKU options, API versions). Instead, use Azure-managed constructs (FQDN tags, service tags) where available, and reference authoritative docs for the rest.

---

## Architecture Overview

The spoke deploys an AKS private cluster and supporting resources **into infrastructure created by the hub**. When `hub_managed = true` in the hub's `spoke_vnets` configuration, the hub creates the spoke resource group and VNet. The spoke deployment consumes these via Terraform remote state and deploys application infrastructure into them.

### Hub Dependency

The spoke deployment MUST run **after** the hub is fully deployed. The spoke reads hub outputs via `terraform_remote_state` to get:

| Hub Output | Spoke Usage |
|---|---|
| `dns_resolver_inbound_ip` | Spoke VNet custom DNS (set by hub when hub_managed) |
| `private_dns_zone_ids` | AKS BYOD DNS zone, ACR/KV private endpoint DNS |
| `log_analytics_workspace_id` | Container Insights, diagnostic settings |
| `firewall_private_ip` | UDR next hop for egress |
| `firewall_policy_id` | Spoke-specific firewall rule collection group |
| `hub_vnet_id` | Reference for peering verification |
| `spoke_vnet_ids` | VNet ID (hub_managed mode) |
| `spoke_resource_group_names` | RG name (hub_managed mode) |

### Component Inventory

Use Azure Verified Modules (AVM) where available. Always check the [AVM Module Index](https://azure.github.io/Azure-Verified-Modules/) for the latest module versions and property names before generating code.

| Component | Purpose | Terraform Module / Resource |
|---|---|---|
| Spoke RG + VNet | Infrastructure container (hub-created) | Consumed via `terraform_remote_state` |
| Subnets | AKS nodes, system, management | Added to hub-created VNet |
| AKS Cluster | Private Kubernetes cluster with CNI Overlay + Cilium | AVM `avm-res-containerservice-managedcluster` |
| Control Plane UAMI | AKS control plane managed identity | `azurerm_user_assigned_identity` |
| Kubelet UAMI | AKS kubelet managed identity | `azurerm_user_assigned_identity` |
| RBAC Assignments | Network, DNS, identity permissions | `azurerm_role_assignment` |
| Route Table + UDR | Egress routing to hub firewall | `azurerm_route_table` + `azurerm_route` |
| NSG | Network security for AKS nodes | `azurerm_network_security_group` |
| ACR | Container image registry with private endpoint | AVM `avm-res-containerregistry-registry` |
| Key Vault | Secrets management with private endpoint | AVM `avm-res-keyvault-vault` |
| Jump Box VM | Management access with pre-installed tooling | `azurerm_linux_virtual_machine` (optional) |
| Diagnostic Settings | AKS log shipping to hub Log Analytics | `azurerm_monitor_diagnostic_setting` |
| Firewall Rule Collection Group | Spoke-specific egress rules | `azurerm_firewall_policy_rule_collection_group` |

---

## Hub-Managed Consumption Pattern

### Resource Group & VNet

When the hub deploys with `hub_managed = true` for this spoke, the hub creates:
- Spoke resource group
- Spoke VNet with custom DNS pointing to hub DNS resolver inbound IP

The spoke deployment MUST NOT create its own RG or VNet. Instead, it references them via hub remote state:

```hcl
# Read hub-created spoke resources
data "terraform_remote_state" "hub" {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-terraform-state-dev"
    storage_account_name = "<backend-storage-account>"
    container_name       = "tfstate-hub"
    key                  = "terraform.tfstate"
    use_azuread_auth     = true
  }
}

locals {
  hub_outputs         = data.terraform_remote_state.hub.outputs
  spoke_rg_name       = local.hub_outputs.spoke_resource_group_names["spoke-aks-prod"]
  spoke_vnet_id       = local.hub_outputs.spoke_vnet_ids["spoke-aks-prod"]
  firewall_private_ip = local.hub_outputs.firewall_private_ip
}
```

### Subnet Provisioning

The hub creates the VNet but does **NOT** create spoke subnets. Subnets are application-specific and owned by the spoke deployment. The spoke uses `azurerm_subnet` resources or the AVM VNet module's subnet capability to add subnets to the hub-created VNet.

**IMPORTANT**: When using `azurerm_subnet` as standalone resources against a hub-created VNet, ensure lifecycle rules prevent conflicts with the hub's VNet module.

---

## Spoke VNet Subnet Layout

### Address Space

- **Spoke VNet CIDR**: `10.1.0.0/16` (set by hub in `spoke_vnets` variable)

### Subnet Layout

| Subnet Key | Name | CIDR | Purpose | Associations |
|---|---|---|---|---|
| `aks_nodes` | aks-nodes | `10.1.0.0/22` | AKS node pool VMs, pods (overlay) | Route table, NSG |
| `aks_system` | aks-system | `10.1.4.0/24` | AKS system components | Route table |
| `management` | management | `10.1.5.0/24` | Jump box VM, private endpoints (ACR, KV) | None |

### Subnet Sizing Guidance

- **AKS nodes subnet** (`/22` = 1,022 IPs): Sized for node scaling. With CNI Overlay, pods get IPs from the `pod_cidr` overlay network (not this subnet), so subnet size only needs to accommodate node count + Azure reserved IPs.
- **Management subnet** (`/24`): Private endpoints and management VMs. Each private endpoint consumes 1 IP.

Consult [AKS subnet planning](https://learn.microsoft.com/en-us/azure/aks/concepts-network-azure-cni-overlay#ip-address-planning) for current sizing guidance.

---

## AKS Cluster Specification

### Network Configuration

| Setting | Value | Rationale |
|---|---|---|
| Network Plugin | `azure` | Azure CNI — required for overlay mode |
| Network Plugin Mode | `overlay` | Pods get IPs from overlay CIDR, preserves VNet address space |
| Network Dataplane | `cilium` | eBPF-based dataplane for high performance |
| Network Policy | `cilium` | L3/L4/L7 policy enforcement via Cilium |
| Pod CIDR | `192.168.0.0/16` | Overlay network — not routable outside cluster |
| Service CIDR | `172.16.0.0/16` | Kubernetes service cluster IPs |
| DNS Service IP | `172.16.0.10` | CoreDNS service IP within service CIDR |
| Load Balancer SKU | `standard` | Required for private clusters |
| Outbound Type | `userDefinedRouting` | Egress through hub Azure Firewall |

Consult [Azure CNI Overlay networking](https://learn.microsoft.com/en-us/azure/aks/concepts-network-azure-cni-overlay) and [Azure CNI powered by Cilium](https://learn.microsoft.com/en-us/azure/aks/azure-cni-powered-by-cilium) for current configuration options and limitations.

#### CNI Overlay + Cilium Best Practices

- **Pod CIDR sizing**: Allow 20-30% headroom for node scaling and upgrades. Each node gets a `/24` from the pod CIDR by default.
- **Overlay pods are not directly routable** from outside the cluster — use LoadBalancer or Ingress for external exposure.
- **Egress**: Overlay pods SNAT through the node's primary IP. UDR on the node subnet directs egress to the firewall.
- **Linux-only**: Cilium on AKS Overlay is Linux-only as of current release. Check [Cilium AKS docs](https://learn.microsoft.com/en-us/azure/aks/azure-cni-powered-by-cilium) for Windows support status.

### Private Cluster Configuration

```hcl
api_server_access_profile = {
  enable_private_cluster             = true
  enable_private_cluster_public_fqdn = false
  private_dns_zone                   = local.hub_outputs.private_dns_zone_ids["privatelink.{region}.azmk8s.io"]
}
```

**CRITICAL**: The AVM module property is `private_dns_zone` (NOT `private_dns_zone_id`). Always verify the property name against the [AVM AKS module variables](https://registry.terraform.io/modules/Azure/avm-res-containerservice-managedcluster/azurerm/latest?tab=inputs).

### SKU Configuration

- **SKU Name**: `Base`
- **SKU Tier**: `Standard` (recommended for production — includes SLA)
- Consult [AKS pricing tiers](https://learn.microsoft.com/en-us/azure/aks/free-standard-pricing-tiers) for current tier options and SLA guarantees.

### Node Pools

| Pool | Type | VM Size | Count | Subnet | Host Encryption |
|---|---|---|---|---|---|
| `system` | System | Configurable (default `Standard_D4s_v3`) | Configurable (default 2) | `aks_nodes` | ✅ Enabled |
| `user` | User | Configurable (default `Standard_D4s_v3`) | Configurable (default 2) | `aks_nodes` | ✅ Enabled |

Consult [AKS VM size recommendations](https://learn.microsoft.com/en-us/azure/aks/quotas-skus-regions) for current size guidance.

### Security Features

| Feature | Default | Notes |
|---|---|---|
| Host Encryption | Enabled | On all node pools |
| Workload Identity | Enabled | OIDC issuer + security profile |
| Azure Policy | Enabled | Policy addon for governance |
| Private Cluster | Enabled | API server accessible only via private network |

---

## DNS Architecture

### How Spoke DNS Resolution Works

The spoke VNet's custom DNS is configured by the hub (when `hub_managed = true`) to point to the hub DNS resolver inbound endpoint. This enables the full resolution chain:

```
AKS Pod/Node
  → CoreDNS (172.16.0.10)
    → Spoke VNet custom DNS (hub resolver IP)
      → Hub DNS Resolver Inbound Endpoint (10.0.6.x)
        → Azure DNS (168.63.129.16) in hub VNet context
          → Private DNS Zone (hub VNet-linked)
            → A record → Private IP
```

### AKS BYOD Private DNS Zone Pattern

The spoke MUST implement the Bring Your Own DNS (BYOD) pattern for the AKS private cluster:

1. **Hub creates** `privatelink.{region}.azmk8s.io` private DNS zone (linked to hub VNet)
2. **Spoke creates** AKS control plane UAMI
3. **Spoke grants** UAMI `Private DNS Zone Contributor` role on the hub's AKS DNS zone
4. **AKS creates** an A record in the zone for the API server private endpoint
5. **AKS nodes** resolve the API server FQDN through the DNS chain above

```hcl
resource "azurerm_role_assignment" "control_plane_to_private_dns_zone" {
  scope                = local.hub_outputs.private_dns_zone_ids["privatelink.{region}.azmk8s.io"]
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.aks_control_plane.principal_id
}
```

Reference: [Use a private DNS zone with AKS](https://learn.microsoft.com/en-us/azure/aks/private-clusters#configure-a-private-dns-zone)

### Spoke VNet DNS Zone Linking — AKS Auto-Creates

Spoke VNets do **not** need Terraform-managed links to private DNS zones. DNS resolution works through the hub DNS resolver chain without any spoke VNet link.

**However**, the AKS resource provider **automatically creates** a VNet link from the spoke VNet to the `privatelink.{region}.azmk8s.io` DNS zone during private cluster provisioning. This is AKS platform behavior — confirmed via both Terraform deployment and manual `az aks create` testing (no Terraform involved). The AKS RP acts through the **control plane UAMI** to create this link, as verified by Azure Activity Log analysis.

**Key facts**:
- **Created by**: The AKS RP, acting through the control plane UAMI (not its own first-party identity). The Activity Log shows the UAMI's `principalId` as the caller and its `clientId` as `claims.appid`.
- **When**: During cluster create and on every cluster start/restart, immediately after writing the API server A record
- **Cannot be prevented**: The required `Private DNS Zone Contributor` role grants `Microsoft.Network/privateDnsZones/*`, which includes both `A/write` and `virtualNetworkLinks/write` — these permissions are inseparable
- **Re-created if removed**: If the VNet link is manually deleted and the cluster is restarted, AKS re-creates it
- **Harmless**: DNS resolution works via the hub resolver chain regardless of whether this link exists
- **Scope**: Applies only to the AKS DNS zone (`privatelink.{region}.azmk8s.io`), not to ACR, Key Vault, or other private endpoint zones
- **Not in Terraform state**: Since the AKS RP creates it, Terraform does not manage or track it — no drift risk

Reference: [Hub and spoke with custom DNS for private AKS clusters](https://learn.microsoft.com/en-us/azure/aks/private-clusters#hub-and-spoke-with-custom-dns-for-private-aks-clusters)

> "If you keep the default private DNS zone behavior, AKS tries to link the zone directly to the spoke VNet that hosts the cluster even when the zone is already linked to a hub VNet."

Known issues: [Azure/AKS#4998](https://github.com/Azure/AKS/issues/4998), [Azure/AKS#4841](https://github.com/Azure/AKS/issues/4841)

#### Verifying VNet Link Creator

Use these `az cli` commands to confirm the control plane UAMI created the spoke VNet link:

```bash
# 1. List VNet links on the AKS private DNS zone
az network private-dns link vnet list \
  --resource-group <hub-rg> \
  --zone-name privatelink.<region>.azmk8s.io \
  -o table

# 2. Query Activity Log for VNet link write operations
az monitor activity-log list \
  --resource-group <hub-rg> \
  --offset 7d \
  --query "[?contains(operationName.value || '', 'privateDnsZones/virtualNetworkLinks/write')].{caller:caller, appId:claims.appid, operation:operationName.value, status:status.value, time:eventTimestamp, resource:resourceId}" \
  -o table

# 3. Look up the control plane UAMI identity
az identity show \
  --name <uami-aks-cp-name> \
  --resource-group <spoke-rg> \
  --query '{name:name, principalId:principalId, clientId:clientId}' \
  -o table

# 4. Cross-reference: the Activity Log 'caller' should match the UAMI's principalId,
#    and 'appId' should match the UAMI's clientId. This confirms the AKS RP acted
#    through the control plane UAMI to create the VNet link.
```

---

## Managed Identity & RBAC Specification

### Identities

| Identity | Name Pattern | Purpose |
|---|---|---|
| Control Plane UAMI | `uami-aks-cp-{env}-{location_code}` | AKS control plane operations, DNS record management |
| Kubelet UAMI | `uami-aks-kubelet-{env}-{location_code}` | Node-level operations, image pulls |

### Required Role Assignments

| Principal | Scope | Role | Purpose |
|---|---|---|---|
| Control Plane UAMI | Kubelet UAMI | `Managed Identity Operator` | AKS manages kubelet identity |
| Control Plane UAMI | Spoke VNet | `Network Contributor` | AKS manages LBs, NICs, routes |
| Control Plane UAMI | Hub AKS DNS Zone | `Private DNS Zone Contributor` | BYOD: write A records and VNet links for API server (see [AKS auto-creates VNet link](#spoke-vnet-dns-zone-linking--aks-auto-creates)) |
| Kubelet UAMI | ACR | `AcrPull` | Pull container images |
| Control Plane UAMI | Key Vault | `Key Vault Secrets User` | Read secrets for workload config |
| Jump Box VM (SystemAssigned) | AKS Cluster | `Azure Kubernetes Service Cluster User Role` | kubectl access from jump box |

### RBAC Propagation Delay

Azure AD role assignments take time to propagate. The spoke MUST include a `time_sleep` resource (90 seconds recommended) between role assignments and AKS cluster creation to ensure the Private DNS Zone Contributor role is active before AKS attempts to register the API server A record.

```hcl
resource "time_sleep" "wait_for_rbac" {
  depends_on = [
    azurerm_role_assignment.control_plane_to_kubelet,
    azurerm_role_assignment.control_plane_to_vnet,
    azurerm_role_assignment.control_plane_to_private_dns_zone
  ]
  create_duration = "90s"
}
```

Reference: [AKS managed identities](https://learn.microsoft.com/en-us/azure/aks/use-managed-identity)

---

## Network Security Specification

### Route Table (UDR)

All AKS node traffic MUST egress through the hub Azure Firewall:

```hcl
resource "azurerm_route" "default_route" {
  name                   = "route-default-to-firewall"
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = local.firewall_private_ip  # From hub remote state
}
```

Associate route table with AKS node subnets (`aks_nodes`, `aks_system`).

### NSG Rules

| Priority | Name | Direction | Source | Destination | Port | Purpose |
|---|---|---|---|---|---|---|
| 100 | AllowIntraSubnet | Inbound | `10.1.0.0/22` | `10.1.0.0/22` | `*` | Node-to-node communication |
| 110 | AllowHttpFromHub | Inbound | `10.0.0.0/16` | `{nginx_lb_ip}` | `80` | HTTP from hub to NGINX LB |
| 120 | AllowHttpsFromHub | Inbound | `10.0.0.0/16` | `{nginx_lb_ip}` | `443` | HTTPS from hub to NGINX LB |
| 130 | AllowHttpFromSpoke | Inbound | `10.1.0.0/16` | `{nginx_lb_ip}` | `80` | HTTP from spoke management subnet |
| 140 | AllowHttpsFromSpoke | Inbound | `10.1.0.0/16` | `{nginx_lb_ip}` | `443` | HTTPS from spoke management subnet |
| 4096 | DenyAllInbound | Inbound | `*` | `*` | `*` | Default deny |

**NSG targeting pattern**: Rules target the NGINX internal load balancer frontend IP (e.g., `10.1.0.50`), NOT the full subnet range. Traffic arrives at the LB frontend IP; Azure LB distributes to backend pods.

### Spoke Firewall Rule Collection Group

The spoke owns its own firewall rules at priority ≥ 500 on the hub's firewall policy:

```hcl
resource "azurerm_firewall_policy_rule_collection_group" "spoke_rules" {
  name               = "rcg-spoke-aks-${var.environment}"
  firewall_policy_id = local.hub_outputs.firewall_policy_id
  priority           = 500  # Must be >= 500 to avoid hub baseline range

  # Spoke-specific application rules (e.g., Ubuntu packages, custom FQDNs)
  application_rule_collection {
    name     = "spoke-dependencies"
    priority = 510
    action   = "Allow"
    # ...rules...
  }
}
```

---

## Supporting Resources

### Azure Container Registry (ACR)

- **SKU**: `Premium` (required for private endpoints)
- **Private Endpoint**: In `management` subnet, DNS zone from hub (`privatelink.azurecr.io`)
- **RBAC**: Kubelet UAMI gets `AcrPull` role
- **Naming**: `acr{env}{location_code}{random_suffix}` (globally unique, alphanumeric only)

Consult [ACR private endpoint](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-private-link) for current configuration.

### Azure Key Vault

- **SKU**: `standard`
- **Private Endpoint**: In `management` subnet, DNS zone from hub (`privatelink.vaultcore.azure.net`)
- **Network ACLs**: Default deny, bypass AzureServices
- **Purge Protection**: Enabled
- **RBAC**: Control plane UAMI gets `Key Vault Secrets User` role
- **Naming**: `kv-{env}-{location_code}-{random_suffix}` (globally unique)

Consult [Key Vault private endpoint](https://learn.microsoft.com/en-us/azure/key-vault/general/private-link-service) for current configuration.

### Private Endpoint Wiring Pattern

All private endpoints follow the same pattern — this is the **standard pattern** for customer extensions too:

```hcl
private_endpoints = {
  my_endpoint = {
    name                            = "pe-{service}-{env}-{location_code}"
    subnet_resource_id              = module.spoke_vnet.subnets["management"].resource_id
    private_dns_zone_resource_ids   = [local.hub_outputs.private_dns_zone_ids["privatelink.{zone}"]]
    private_service_connection_name = "psc-{service}-{env}-{location_code}"
  }
}
```

**Key**: DNS zone IDs come from the hub. The hub owns the private DNS zones; the spoke only references them. If a spoke needs a DNS zone not yet in the hub, the hub spec must be updated first.

---

## Web App Routing (NGINX Ingress)

### Two-Step Deployment Pattern

1. **Terraform** enables the Web App Routing add-on at the infrastructure level
2. **Kubernetes manifest** configures the NginxIngressController CRD for internal load balancer

This keeps infrastructure provisioning separate from Kubernetes configuration and avoids the Terraform `kubernetes` provider dependency on cluster credentials.

**Automated in pipeline**: The spoke pipeline (`spoke-deploy.yml`) includes a `PostDeploy` stage that automatically applies the NGINX manifest via `kubectl` after Terraform apply. The CI/CD self-hosted agents can reach the private AKS API server through direct CI/CD ↔ spoke VNet peering.

```hcl
# Step 1: Terraform enables the add-on
ingress_profile = {
  web_app_routing = {
    enabled               = true
    dns_zone_resource_ids = var.web_app_routing_dns_zone_ids
  }
}
```

```yaml
# Step 2: Post-deployment Kubernetes manifest (manifests/nginx-internal-controller.yaml)
apiVersion: approuting.kubernetes.azure.com/v1alpha1
kind: NginxIngressController
metadata:
  name: nginx-internal
spec:
  ingressClassName: nginx-internal
  controllerNamePrefix: nginx-internal
  loadBalancerAnnotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
    service.beta.kubernetes.io/azure-load-balancer-internal-subnet: "aks-nodes"
    service.beta.kubernetes.io/azure-load-balancer-ipv4: "{nginx_internal_lb_ip}"
```

Reference: [Web Application Routing add-on](https://learn.microsoft.com/en-us/azure/aks/web-app-routing)

---

## Jump Box VM Specification

- **Conditional deployment**: Controlled by feature flag
- **SKU**: Configurable (default `Standard_D2s_v3`)
- **OS**: Latest Ubuntu LTS (Gen2)
- **Identity**: SystemAssigned managed identity → AKS Cluster User Role
- **Subnet**: `management`
- **Pre-installed tools**: Azure CLI, kubectl, Helm, k9s, jq, vim, curl, wget, git
- **Security**: All binary downloads MUST be checksum-verified. Never pipe remote scripts to bash.

Consult hub spec (`hub-deploy.instructions.md`) Jump Box section for security best practices.

---

## Diagnostic Settings

AKS diagnostic logs ship to the hub's centralized Log Analytics Workspace:

| Log Category | Purpose |
|---|---|
| `kube-apiserver` | API server audit and request logs |
| `kube-controller-manager` | Controller reconciliation logs |
| `kube-scheduler` | Pod scheduling decisions |
| `kube-audit` | Kubernetes audit events |
| `cluster-autoscaler` | Autoscaler decisions (when enabled) |
| `AllMetrics` | AKS platform metrics |

Consult [AKS monitoring reference](https://learn.microsoft.com/en-us/azure/aks/monitor-aks-reference) for the current list of available log categories.

---

## Customer Extensions

### How It Works

Customers add Azure resources to the spoke by creating **GitHub Issues** using the `Add Spoke Resource` issue template. The workflow:

1. **Customer** creates a GitHub Issue describing the resource they need (type, SKU, connectivity, RBAC)
2. **Copilot Coding Agent** reads the issue + this spec
3. **Copilot generates** a `custom-*.tf` file following the conventions below
4. **Copilot opens a PR** linked to the issue
5. **Human reviews** the PR, approves
6. **Pipeline deploys** the changes

### File Naming Convention

Custom resource files MUST be prefixed with `custom-` to distinguish them from core spoke infrastructure:

```
infra/terraform/spoke/
├── main.tf                  ← Core spoke resources (DO NOT MODIFY)
├── variables.tf             ← Core variables (DO NOT MODIFY)
├── outputs.tf               ← Core outputs (DO NOT MODIFY)
├── custom-cosmosdb.tf       ← Customer resource: Cosmos DB
├── custom-appgateway.tf     ← Customer resource: App Gateway
├── custom-variables.tf      ← Customer-specific variables
├── custom-outputs.tf        ← Customer-specific outputs
```

### Available References

Copilot-generated `custom-*.tf` files can reference these existing resources:

| Reference | Type | Description |
|---|---|---|
| `local.hub_outputs.private_dns_zone_ids` | Map | Hub private DNS zone IDs by zone name |
| `local.hub_outputs.log_analytics_workspace_id` | String | Centralized monitoring workspace |
| `local.hub_outputs.firewall_policy_id` | String | Hub firewall policy (for rule groups) |
| `local.hub_outputs.firewall_private_ip` | String | Firewall IP for UDR |
| `module.spoke_vnet.subnets["management"].resource_id` | String | Management subnet for private endpoints |
| `module.spoke_vnet.subnets["aks_nodes"].resource_id` | String | AKS node subnet |
| `module.aks_cluster.resource_id` | String | AKS cluster resource ID |
| `azurerm_resource_group.aks_spoke.name` | String | Spoke resource group name |
| `azurerm_resource_group.aks_spoke.location` | String | Spoke location |
| `azurerm_user_assigned_identity.aks_control_plane` | Resource | AKS control plane identity |
| `azurerm_user_assigned_identity.aks_kubelet` | Resource | AKS kubelet identity |
| `local.common_tags` | Map | Standard resource tags |
| `var.environment` | String | Environment name (prod, dev, etc.) |
| `local.location_code` | String | Location abbreviation (eus2, wus2, etc.) |

### Rules for Copilot-Generated Resources

When generating `custom-*.tf` files, Copilot MUST:

1. **Use AVM modules** where available — check [AVM Module Index](https://azure.github.io/Azure-Verified-Modules/)
2. **Wire private endpoints** to hub DNS zones using the pattern in "Private Endpoint Wiring Pattern" above
3. **Set `enable_telemetry = true`** on all AVM modules
4. **Apply `local.common_tags`** to all resources
5. **Follow naming convention**: `{resource-type}-{purpose}-{env}-{location_code}`
6. **Add diagnostic settings** shipping to `local.hub_outputs.log_analytics_workspace_id`
7. **Request new hub DNS zones** if the resource needs a zone not in the hub — update hub spec + hub code first
8. **Place private endpoints** in the `management` subnet
9. **Never modify core files** (`main.tf`, `variables.tf`, `outputs.tf`, `locals.tf`, `data-sources.tf`)
10. **Put new variables** in `custom-variables.tf` and new outputs in `custom-outputs.tf`

### Example: Adding Cosmos DB

```hcl
# custom-cosmosdb.tf — generated from GitHub Issue #42
module "cosmosdb" {
  source  = "Azure/avm-res-documentdb-databaseaccount/azurerm"
  version = "~> 0.1"  # Check AVM Module Index for latest

  name                = "cosmos-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.aks_spoke.name
  location            = azurerm_resource_group.aks_spoke.location

  # Private endpoint in management subnet, DNS zone from hub
  private_endpoints = {
    cosmos_pe = {
      name                          = "pe-cosmos-${var.environment}-${local.location_code}"
      subnet_resource_id            = module.spoke_vnet.subnets["management"].resource_id
      private_dns_zone_resource_ids = [local.hub_outputs.private_dns_zone_ids["privatelink.documents.azure.com"]]
    }
  }

  enable_telemetry = true
  tags             = local.common_tags
}
```

---

## Naming Conventions

All resources follow the pattern: `{resource-type}-{purpose}-{environment}-{location_code}`

Consult [Azure naming conventions](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming) and [abbreviation recommendations](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations) for current best practices.

| Resource | Naming Pattern | Example |
|---|---|---|
| Resource Group | `rg-aks-{location_code}-{env}` | `rg-aks-eus2-prod` |
| VNet | `vnet-aks-{env}-{location_code}` | `vnet-aks-prod-eus2` |
| AKS Cluster | `aks-{workload}-{env}-{location_code}` | `aks-eco-prod-eus2` |
| Control Plane UAMI | `uami-aks-cp-{env}-{location_code}` | `uami-aks-cp-prod-eus2` |
| Kubelet UAMI | `uami-aks-kubelet-{env}-{location_code}` | `uami-aks-kubelet-prod-eus2` |
| Route Table | `rt-spoke-{env}-{location_code}` | `rt-spoke-prod-eus2` |
| NSG | `nsg-aks-nodes-{env}-{location_code}` | `nsg-aks-nodes-prod-eus2` |
| ACR | `acr{env}{location_code}{suffix}` | `acrprodeus2abc123` |
| Key Vault | `kv-{env}-{location_code}-{suffix}` | `kv-prod-eus2-abc123` |
| Jump Box | `vm-jumpbox-spoke-{location_code}-{env}` | `vm-jumpbox-spoke-eus2-prod` |

---

## Deployment Order & Dependencies

### CRITICAL: Deploy hub BEFORE spoke

```
Phase 1: Hub deployment (see hub-deploy.instructions.md)
  └─→ Hub RG, VNet, Firewall, Bastion, DNS Resolver, Log Analytics
  └─→ Private DNS Zones (linked to hub VNet)
  └─→ Spoke RG + VNet (hub_managed, custom DNS → hub resolver)
  └─→ Bidirectional VNet Peering

Phase 2: Spoke deployment (this spec)
  └─→ Read hub remote state
  └─→ Subnets (into hub-created VNet)
  └─→ UAMI identities (control plane + kubelet)
  └─→ RBAC role assignments
  └─→ Route table + UDR to hub firewall
  └─→ NSG for AKS nodes
  └─→ Wait for RBAC propagation (90s)
  └─→ AKS cluster (private, CNI Overlay + Cilium)
  └─→ ACR + private endpoint
  └─→ Key Vault + private endpoint
  └─→ Jump Box VM (optional)
  └─→ Diagnostic settings
  └─→ Spoke firewall rule collection group (priority ≥ 500)

Phase 3: Post-deployment (automated via spoke pipeline PostDeploy stage)
  └─→ Apply NginxIngressController Kubernetes manifest via kubectl
  └─→ Verify NGINX controller ready and internal LB IP assigned
  └─→ Verify DNS resolution from jump box
  └─→ Validate AKS connectivity
```

---

## Outputs

| Output | Description | Consumer |
|---|---|---|
| `resource_group_name` | Spoke RG name | Workload deployments |
| `aks_cluster_id` | AKS cluster resource ID | Workload deployments, RBAC |
| `aks_cluster_name` | AKS cluster name | kubectl/az aks commands |
| `aks_private_fqdn` | AKS API server private FQDN | kubectl configuration |
| `aks_oidc_issuer_url` | OIDC issuer URL | Workload identity federation |
| `aks_kubelet_identity_client_id` | Kubelet identity client ID | ACR pull configuration |
| `acr_id` | ACR resource ID | Image push automation |
| `acr_login_server` | ACR login server FQDN | Docker/Helm push |
| `key_vault_id` | Key Vault resource ID | Secret management |
| `key_vault_uri` | Key Vault URI | Application secret access |
| `spoke_vnet_id` | Spoke VNet resource ID | Cross-reference |
| `nginx_internal_lb_ip` | NGINX internal LB IP | Ingress configuration |

---

## Pre-Flight Checklist

Before deploying spoke infrastructure:

1. **Verify hub is deployed** — `terraform_remote_state.hub` must return valid outputs
2. **Verify hub-created spoke RG + VNet exist** — check `spoke_vnet_ids` and `spoke_resource_group_names` outputs
3. **Verify Azure authentication** — `az account show` confirms correct subscription
4. **Verify DNS zones exist in hub** — `private_dns_zone_ids` output must include AKS, ACR, KV zones
5. **Verify backend storage access** — enable public network access if needed
6. **Check AKS quota** — verify VM quota in target region for node pool sizes

---

## Validation After Deployment

```bash
# 1. Verify AKS cluster is running
az aks show --name <aks-name> --resource-group <rg-name> --query "provisioningState"

# 2. Verify DNS resolution from jump box (via Bastion)
nslookup <aks-private-fqdn>
# Should resolve to private IP via hub DNS resolver chain

# 3. Verify private endpoints
nslookup <acr-login-server>
nslookup <kv-name>.vault.azure.net
# Both should resolve to private IPs

# 4. Verify kubectl access from jump box
az aks get-credentials --name <aks-name> --resource-group <rg-name>
kubectl get nodes

# 5. Verify NGINX internal LB (after manifest applied)
kubectl get svc -n app-routing-system
# Should show internal LB with configured IP
```

---

## Related Documentation

- Hub spec: `.github/instructions/hub-deploy.instructions.md`
- ADO pipeline spec: `.github/instructions/ado-pipeline-setup.instructions.md`
- Terraform deployment workflow: `.github/instructions/terraform-deploy.instructions.md`
- Terraform destroy workflow: `.github/instructions/terraform-destroy.instructions.md`
- AVM usage: `.github/instructions/azure-verified-modules-terraform.instructions.md`
- Kubernetes manifests: `infra/terraform/spoke/manifests/`
