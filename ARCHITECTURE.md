# AKS Landing Zone — Architecture Overview

> Generated for import into [Eraser.io](https://eraser.io) AI diagram generator.
> This document describes the full hub-spoke network topology across three landing zones:
> CI/CD, Hub, and Spoke (AKS).

---

## System Overview

The architecture implements an Azure hub-spoke network topology for a production-grade private AKS landing zone. Three logically separate Azure landing zones are deployed in sequence and interconnected via VNet peering.

- **CI/CD Landing Zone**: Self-contained pipeline infrastructure. Hosts self-hosted Azure DevOps agents running as Container App Jobs on a dedicated VNet. Deploys before the hub (bootstrap pattern). Connects to Hub and Spoke via VNet peering.
- **Hub Landing Zone**: Centralized connectivity, security, and shared services. Provides Azure Firewall for egress control, Azure Bastion for secure access, a Private DNS Resolver for centralized DNS, Log Analytics Workspace for monitoring, and Private DNS Zones for all Azure PaaS services.
- **Spoke (AKS) Landing Zone**: Application workload environment. Contains a private AKS cluster (Azure CNI Overlay + Cilium), Azure Container Registry, Azure Key Vault, and an internal NGINX ingress controller. The Spoke VNet is created by the Hub (hub_managed pattern) and AKS resources are deployed into it.

All inter-VNet traffic flows through the Hub. Spoke workloads egress through the Hub Azure Firewall via User-Defined Routes.

---

## Landing Zone 1: CI/CD

### Resource Group
- `rg-cicd-eus2-prod` — contains all CI/CD resources

### Virtual Network
- Name: `vnet-cicd-prod-eus2`
- Address space: `10.2.0.0/24`
- Custom DNS: Hub DNS Resolver Inbound IP (set during Day 2 integration)

### Subnets
- `container-app` (`10.2.0.0/27`) — delegated to `Microsoft.App/environments`, hosts Container App Job agents
- `aci-agents-acr` (`10.2.0.32/29`) — private endpoint for module-managed ACR
- `private-endpoints` (`10.2.0.48/28`) — private endpoints for State SA and Platform Key Vault

### Compute
- **Container App Environment** — KEDA-scaled Container App Jobs for self-hosted ADO pipeline agents
- Agent pool name: `aci-cicd-pool`
- Scale: 0 to 10 concurrent jobs
- Authentication: User-Assigned Managed Identity (no PAT)

### Managed Identity
- `uami-cicd-agents-prod-eus2` — authenticates agents with ADO and reads secrets from Platform Key Vault

### Container Registry (module-managed)
- Premium SKU ACR — hosts the self-hosted agent container image
- ACR Tasks — automatically rebuilds image when Microsoft base image updates
- Private endpoint in `aci-agents-acr` subnet

### Networking Components
- **NAT Gateway** (`natgw-cicd-prod-eus2`) — outbound internet connectivity for Container App subnet (UDRs not supported on delegated subnets)
- Public IP for NAT Gateway (Static, Standard SKU)

### Private Endpoints (in `private-endpoints` subnet)
- State Storage Account PE — CI/CD Terraform state backend
- Hub+Spoke State Storage Account PE — allows agents to read hub/spoke Terraform state
- Platform Key Vault PE — agents read SSH keys and platform secrets during Terraform apply

### DNS Zones (CI/CD-owned, used during bootstrap before hub exists)
- `privatelink.azurecr.io` — conditionally created when hub ACR zone not available
- `privatelink.blob.core.windows.net` — CI/CD VNet-linked
- `privatelink.vaultcore.azure.net` — CI/CD VNet-linked

### VNet Peerings
- `peer-cicd-to-hub` → Hub VNet (allows agents to reach hub resources)
- `peer-hub-to-cicd` → Hub VNet (reverse, hub can reach CI/CD)
- `peer-cicd-to-spoke` → Spoke VNet (allows agents to reach private AKS API server)
- `peer-spoke-to-cicd` → Spoke VNet (reverse)

### RBAC
- `uami-cicd-agents-prod-eus2` → `Key Vault Secrets User` on Platform Key Vault

---

## Landing Zone 2: Hub

### Resource Group
- `rg-hub-eus2-prod` — contains all hub resources

### Virtual Network
- Name: `vnet-hub-prod-eus2`
- Address space: `10.0.0.0/16`

### Subnets
- `AzureFirewallSubnet` (`10.0.1.0/26`) — Azure Firewall (name is Azure-mandated)
- `AzureBastionSubnet` (`10.0.2.0/27`) — Azure Bastion (name is Azure-mandated)
- `GatewaySubnet` (`10.0.3.0/27`) — reserved for VPN/ExpressRoute
- `management` (`10.0.4.0/24`) — Jump box VM, management tooling
- `dns-resolver-inbound` (`10.0.6.0/28`) — DNS Resolver inbound endpoint, delegated to `Microsoft.Network/dnsResolvers`
- `dns-resolver-outbound` (`10.0.7.0/28`) — DNS Resolver outbound endpoint, delegated to `Microsoft.Network/dnsResolvers`

### Azure Firewall
- Name: `afw-hub-prod-eus2`
- SKU: AZFW_VNet Standard
- Policy: `afwpol-hub-prod-eus2`
- Public IP: Static Standard SKU
- **Hub Baseline Rules** (priority 100-499):
  - AKS FQDN tag `AzureKubernetesService` (port 443) — all AKS egress dependencies
  - AKS network rules (NTP, DNS, Azure service tags)
- **Spoke Rule Collection Group** (priority 500+): spoke-specific rules added by spoke deployment

### Azure Bastion
- Name: `bas-hub-prod-eus2`
- SKU: Standard
- Enables browser-based RDP/SSH to jump box and management VMs

### Private DNS Resolver
- Name: `dnspr-hub-prod-eus2`
- **Inbound Endpoint** (`10.0.6.x`): receives DNS queries from all spoke VNets via custom DNS setting
- **Outbound Endpoint** (`10.0.7.x`): forwards to corporate/on-premises DNS
- **Forwarding Ruleset**: linked to hub VNet; conditional rules for on-premises domains

### Log Analytics Workspace
- Name: `law-hub-prod-eus2`
- Retention: configurable
- Consumers: all spoke diagnostic settings, AKS Container Insights

### Jump Box VM
- Name: `vm-jumpbox-hub-eus2-prod`
- OS: Ubuntu LTS (Gen2)
- Subnet: `management`
- Pre-installed: Azure CLI, kubectl, Helm, k9s, jq
- Identity: SystemAssigned

### Private DNS Zones (all linked to hub VNet)
- `privatelink.<region>.azmk8s.io` — AKS API server (BYOD pattern)
- `privatelink.azurecr.io` — Azure Container Registry
- `privatelink.vaultcore.azure.net` — Azure Key Vault
- `privatelink.blob.core.windows.net` — Azure Blob Storage
- `privatelink.file.core.windows.net` — Azure Files
- `privatelink.queue.core.windows.net` — Azure Queue
- `privatelink.table.core.windows.net` — Azure Table
- `privatelink.monitor.azure.com` — Azure Monitor
- `privatelink.oms.opinsights.azure.com` — Log Analytics

### Hub-Managed Spoke Resources
Created by hub when `hub_managed = true`:
- Spoke Resource Group: `rg-aks-eus2-prod`
- Spoke VNet: `vnet-aks-prod-eus2` (`10.1.0.0/16`), custom DNS → Hub DNS Resolver Inbound IP

### VNet Peerings
- `peer-hub-to-spoke` → Spoke VNet (allows hub to reach spoke resources)
- `peer-spoke-to-hub` → Spoke VNet (reverse, enables egress through hub firewall)
- `peer-hub-to-cicd` → CI/CD VNet
- `peer-cicd-to-hub` → CI/CD VNet (reverse)

---

## Landing Zone 3: Spoke (AKS)

### Resource Group (hub-managed)
- `rg-aks-eus2-prod` — created by hub deployment

### Virtual Network (hub-managed)
- Name: `vnet-aks-prod-eus2`
- Address space: `10.1.0.0/16`
- Custom DNS: Hub DNS Resolver Inbound IP (`10.0.6.x`)

### Subnets (spoke-owned, added to hub-created VNet)
- `aks-nodes` (`10.1.0.0/22`) — AKS node VMs; associated with Route Table and NSG
- `aks-system` (`10.1.4.0/24`) — AKS system components; associated with Route Table
- `management` (`10.1.5.0/24`) — Jump box VM, private endpoints for ACR and Key Vault

### AKS Cluster
- Name: `aks-eco-prod-eus2`
- Private cluster: API server accessible only from peered VNets
- SKU: Base/Standard (includes SLA)
- **Networking**:
  - Network plugin: Azure (CNI)
  - Network plugin mode: Overlay
  - Network dataplane: Cilium
  - Network policy: Cilium
  - Pod CIDR: `192.168.0.0/16` (overlay, not routable externally)
  - Service CIDR: `172.16.0.0/16`
  - DNS service IP: `172.16.0.10`
  - Outbound type: userDefinedRouting (egress through hub firewall)
  - Load balancer SKU: Standard
- **Node Pools**:
  - System pool: `Standard_D4s_v3`, 2 nodes, aks-nodes subnet, host encryption enabled
  - User pool: `Standard_D4s_v3`, 2 nodes, aks-nodes subnet, host encryption enabled
- **Security features**: Host encryption, Workload Identity (OIDC), Azure Policy addon
- **Add-ons**: Web App Routing (NGINX Ingress), Container Insights → hub Log Analytics
- **API server access**: Private DNS zone `privatelink.<region>.azmk8s.io` (BYOD, hub-owned)

### AKS BYOD Private DNS (BYOD Pattern)
1. Hub creates `privatelink.<region>.azmk8s.io` zone, linked to hub VNet
2. Spoke grants AKS control plane UAMI `Private DNS Zone Contributor` on hub zone
3. AKS writes API server A record into hub zone
4. AKS nodes resolve API server FQDN via custom DNS → Hub DNS Resolver → hub zone

### Managed Identities
- `uami-aks-cp-prod-eus2` (Control Plane UAMI):
  - `Managed Identity Operator` on Kubelet UAMI
  - `Network Contributor` on Spoke VNet
  - `Private DNS Zone Contributor` on Hub AKS DNS Zone
  - `Key Vault Secrets User` on Key Vault
- `uami-aks-kubelet-prod-eus2` (Kubelet UAMI):
  - `AcrPull` on ACR

### Route Table & UDR
- `rt-spoke-prod-eus2` — attached to `aks-nodes` and `aks-system` subnets
- Default route `0.0.0.0/0` → Hub Azure Firewall private IP
- Forces all egress through hub for centralized inspection and control

### Network Security Group
- `nsg-aks-nodes-prod-eus2` — attached to `aks-nodes` subnet
- Rules target NGINX internal LB frontend IP (`10.1.0.50`)
- Allows inbound HTTP/HTTPS from hub (`10.0.0.0/16`) and spoke (`10.1.0.0/16`)
- Allows intra-subnet node-to-node communication
- Denies all other inbound (priority 4096)

### Azure Container Registry
- Name: `acr<env><location><suffix>`
- SKU: Premium (required for private endpoint)
- Private endpoint in `management` subnet, DNS zone: hub `privatelink.azurecr.io`
- Kubelet UAMI → `AcrPull` role

### Azure Key Vault
- Name: `kv-prod-eus2-<suffix>`
- SKU: Standard
- Purge protection: enabled
- Private endpoint in `management` subnet, DNS zone: hub `privatelink.vaultcore.azure.net`
- Control plane UAMI → `Key Vault Secrets User`

### Jump Box VM (optional)
- Name: `vm-jumpbox-spoke-eus2-prod`
- Subnet: `management`
- SystemAssigned identity → `Azure Kubernetes Service Cluster User Role` on AKS cluster
- Pre-installed: Azure CLI, kubectl, Helm, k9s

### NGINX Internal Load Balancer
- Web App Routing add-on enabled at Terraform level
- NginxIngressController CRD applied via post-deployment kubectl
- Internal load balancer IP: `10.1.0.50` (aks-nodes subnet)
- IngressClassName: `nginx-internal`

### Spoke Firewall Rule Collection Group
- `rcg-spoke-aks-prod` attached to hub firewall policy
- Priority 500+ (above hub baseline range of 100-499)
- Contains spoke-specific application rules (Ubuntu packages, custom FQDNs)

### Diagnostic Settings
- AKS logs → hub Log Analytics Workspace
- Categories: kube-apiserver, kube-controller-manager, kube-scheduler, kube-audit, cluster-autoscaler, AllMetrics

---

## Cross-Cutting Flows

### DNS Resolution Chain (Spoke Pod → Private Endpoint)
```
AKS Pod/Node
  → CoreDNS (172.16.0.10)
    → Spoke VNet custom DNS (Hub DNS Resolver Inbound: 10.0.6.x)
      → Azure DNS (168.63.129.16) via Hub VNet
        → Private DNS Zone (linked to Hub VNet)
          → A record → Private IP of target resource
```
This chain applies to: AKS API server FQDN, ACR login server, Key Vault URI, all storage endpoints.

### Egress Path (Spoke Workload → Internet)
```
AKS Pod
  → Pod SNAT → Node IP (CNI Overlay)
    → aks-nodes subnet
      → UDR: 0.0.0.0/0 → Hub Firewall private IP
        → Azure Firewall (hub)
          → Firewall rules: allow AzureKubernetesService FQDN tag, AKS network rules, spoke-specific rules
            → Internet
```

### CI/CD Agent → Private AKS API Server
```
Container App Job (CI/CD Agent, 10.2.x.x)
  → CI/CD VNet
    → VNet Peering: CI/CD ↔ Spoke (direct, non-transitive)
      → Spoke VNet (10.1.x.x)
        → AKS private API server (resolved via DNS chain)
          → kubectl apply / helm upgrade / terraform plan
```
Note: Peering is NOT transitive. CI/CD cannot reach spoke through hub. Direct CI/CD ↔ Spoke peering is required.

### Pipeline Authentication (OIDC, No Secrets)
```
ADO Pipeline
  → AzureCLI@2 task (addSpnToEnvironment: true)
    → Exports: servicePrincipalId, tenantId, idToken (OIDC)
      → Terraform: ARM_USE_OIDC=true, ARM_CLIENT_ID, ARM_OIDC_TOKEN
        → Azure RM Provider + Backend: OIDC token exchange → Azure AD → access token
          → Deploy resources / read/write state
```

### Deployment Sequence
```
Phase 1: CI/CD (bootstrap — MS-hosted agents)
  ↓ UAMI registered in ADO Project Collection Service Accounts
Phase 2: Hub (self-hosted agents, aci-cicd-pool)
  ↓ Creates spoke RG + VNet (hub_managed)
Phase 3: CI/CD Day 2 (⚠️ MS-hosted — VNet/DNS changes recreate Container App Environment)
  ↓ Adds peerings (CI/CD↔Hub, CI/CD↔Spoke), hub DNS zones
Phase 4: Spoke (self-hosted agents, aci-cicd-pool)
  ↓ AKS, ACR, KV, NGINX manifest
```

---

## Key Design Decisions

| Decision | Rationale |
|---|---|
| Orphan CI/CD landing zone (not in hub) | Separation of duties: hub owns connectivity, CI/CD owns platform tooling (CAF pattern) |
| NAT Gateway for CI/CD egress | Container App delegated subnets do not support UDRs; NAT Gateway is the only egress option |
| Direct CI/CD ↔ Spoke peering | VNet peering is NOT transitive; agents cannot reach spoke through hub |
| CNI Overlay + Cilium | Preserves VNet address space (pods use overlay CIDR); Cilium provides eBPF-based L3/L4/L7 policy |
| BYOD private DNS zone for AKS | Centralized DNS zones in hub, linked only to hub VNet; AKS control plane UAMI writes A records |
| Hub DNS Resolver (no spoke zone links) | All spokes resolve via custom DNS → hub resolver → hub VNet-linked zones; no Terraform-managed spoke VNet links needed |
| `userDefinedRouting` outbound type | All AKS egress through hub Azure Firewall for centralized policy enforcement |
| `AzureKubernetesService` FQDN tag | Auto-maintained by Microsoft; eliminates manual FQDN list management |
| Bootstrap-first CI/CD | CI/CD deploys before hub exists; hub variables are optional with empty-string defaults |
| OIDC authentication (no stored credentials) | Workload Identity Federation eliminates PAT/secret rotation risk in ADO pipelines |
