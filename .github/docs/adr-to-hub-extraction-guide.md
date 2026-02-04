# ADR-to-Hub Extraction Guide

**Purpose**: Extract Hub infrastructure requirements from customer Architecture Decision Records (ADR) aligned with Azure Well-Architected Framework (WAF) pillars.

**Use This If**: Your customer has already documented their architecture decisions and provided an ADR document.

**WAF Alignment**: This guide maps customer ADR decisions to the 5 pillars: Reliability, Security, Cost Optimization, Operational Excellence, and Performance Efficiency.

---

## 📋 Expected ADR Format

Customer ADR should include these sections across the 5 WAF pillars:

```
# Customer Name - Architecture Decision Record

## Hub Infrastructure (Shared Platform Services)

### RELIABILITY (Pillar 1)
- Availability Requirements: [RPO/RTO targets]
- Redundancy Strategy: [Availability zones, multi-region]
- Backup/Restore: [Strategy, frequency, retention]
- Disaster Recovery: [Active-passive, active-active]
- SLA Requirements: [Required uptime %]
- High Availability: [Multi-zone, multi-region]

### SECURITY (Pillar 2)
- Firewall: [Type, e.g., Azure Firewall]
- Egress Control: [How outbound traffic is controlled]
- Ingress: [Type, e.g., Application Gateway + WAF]
- Identity Provider: [e.g., Microsoft Entra ID]
- Access Model: [Azure RBAC / Kubernetes RBAC]
- Private Endpoints: [How managed]
- Azure Policy: [Scope and rules]
- Network Policies: [Enforcement method]
- Compliance: [PCI-DSS, HIPAA, SOC2, etc.]

### COST OPTIMIZATION (Pillar 3)
- VM SKU Strategy: [D-series, E-series, ARM, Spot]
- Commitment: [Savings plans, Reservations]
- Hub Scaling: [Min/max nodes, policies]
- Cost Allocation: [Shared vs per-spoke]
- Reserved Capacity: [For critical components]

### OPERATIONAL EXCELLENCE (Pillar 4)
- IaC Approach: [Terraform, Bicep, Helm]
- GitOps: [Flux, ArgoCD, or none]
- CI/CD Pipeline: [GitHub Actions, Azure DevOps, other]
- Observability: [Log Analytics, Application Insights]
- Monitoring: [Azure Monitor baseline]
- Node Image Updates: [Strategy, frequency]
- Incident Response: [Escalation, on-call]

### PERFORMANCE EFFICIENCY (Pillar 5)
- Expected Scale: [Number of nodes, pods, spokes]
- Performance Targets: [Latency, QPS, throughput SLAs]
- Autoscaling Strategy: [Min/max nodes, metrics]
- DNS Optimization: [Local DNS, caching]
- Network Throughput: [Expected egress/ingress]
- Workload Distribution: [How workloads separated]

### HYBRID CONNECTIVITY
- Connectivity Type: [ExpressRoute / VPN / None]
- Routing: [How traffic flows through hub]
- DNS: [Private DNS configuration]

```

---

## 🔍 Hub Extraction Checklist (WAF-Aligned)

Use this comprehensive checklist to extract Hub requirements from the ADR:

### ✅ Reliability Checklist
- [ ] **RPO/RTO Targets**: _____________ (e.g., 4-hour RPO, 1-hour RTO)
- [ ] **Availability Zones**: _____________ (Single zone / Multi-zone)
- [ ] **Multi-Region Strategy**: _____________ (Yes / No)
- [ ] **Backup/Restore Frequency**: _____________ (Daily / Weekly / Real-time)
- [ ] **Backup Retention**: _____________ (days/months)
- [ ] **Disaster Recovery Mode**: _____________ (Active-passive / Active-active)
- [ ] **Required SLA**: _____________ (e.g., 99.9% / 99.99%)
- [ ] **Hub Redundancy**: _____________ (Single / Multiple instances)

### ✅ Security Checklist
- [ ] **Firewall Type**: _____________ (Azure Firewall / Third-party / None)
- [ ] **Egress Control**: _____________ (Centralized / Per-spoke)

INGRESS ARCHITECTURE:
- [ ] **Traffic Sources**: _____________ (Internet / Azure-internal / On-prem / Hybrid)
- [ ] **Public Internet Access Required**: _____________ (Yes / No / Future)

TIER 1 (External Entry Point):
- [ ] **Tier 1 Service**: _____________ (Front Door / App Gateway / None)
- [ ] **Tier 1 Frontend**: _____________ (Public / Private)
- [ ] **Tier 1 WAF**: _____________ (Yes / No)

TIER 2 (AKS Ingress):
- [ ] **Tier 2 Controller**: _____________ (AGFC / NGINX / Istio / AGIC / LoadBalancer / None)
- [ ] **Tier 2 Frontend**: _____________ (Private / Internal)
- [ ] **Tier 2 WAF**: _____________ (Yes / No)

- [ ] **Identity Provider**: _____________ (Entra ID / Other)
- [ ] **Access Control**: _____________ (RBAC / Custom)
- [ ] **Private Endpoints**: _____________ (Centralized / Per-service)
- [ ] **Azure Policy Scope**: _____________ (Platform / Per-subscription)
- [ ] **Network Policy Engine**: _____________ (Cilium / Azure NPM / Calico)
- [ ] **Compliance Requirements**: _____________ (PCI-DSS / HIPAA / SOC2 / None)
- [ ] **Privileged Access**: _____________ (PIM / Manual / None)

### ✅ Cost Optimization Checklist
- [ ] **Compute SKU Strategy**: _____________ (D-series / E-series / ARM / Spot)
- [ ] **Reservation/Savings Plan**: _____________ (Yes / No / Specific %commitment)
- [ ] **Min Nodes for Hub**: _____________ (e.g., 2 / 3 / 5)
- [ ] **Max Nodes for Hub**: _____________ (e.g., 10 / 20 / Unlimited)
- [ ] **Cost Allocation Model**: _____________ (Shared / Per-spoke chargeback)
- [ ] **Spot VM Usage**: _____________ (Yes / No / Percentage)

### ✅ Operational Excellence Checklist
- [ ] **IaC Tool**: _____________ (Terraform / Bicep / Helm / Other)
- [ ] **GitOps Platform**: _____________ (Flux / ArgoCD / None)
- [ ] **CI/CD Tool**: _____________ (GitHub Actions / Azure DevOps / Other)
- [ ] **Observability Backend**: _____________ (Log Analytics / Datadog / Other)
- [ ] **Monitoring Baseline**: _____________ (Custom / Azure Monitor / Third-party)
- [ ] **Node Image Update Strategy**: _____________ (Automatic / Manual / Kured)
- [ ] **Incident Response**: _____________ (Escalation path, on-call team)
- [ ] **Disaster Recovery Drills**: _____________ (Frequency: Weekly / Monthly / Quarterly)

### ✅ Performance Efficiency Checklist
- [ ] **Expected Hub Scale**: _____________ (Number of nodes)
- [ ] **Expected Spoke Count**: _____________ (Number of AKS clusters)
- [ ] **Total Pod Density**: _____________ (Estimated pod count)
- [ ] **Latency SLA**: _____________ (e.g., <100ms, <50ms)
- [ ] **Throughput SLA**: _____________ (e.g., 10,000 QPS)
- [ ] **Autoscaling Min Nodes**: _____________ (e.g., 2 / 3 / 5)
- [ ] **Autoscaling Max Nodes**: _____________ (e.g., 20 / 50 / 100)
- [ ] **DNS Resolution Strategy**: _____________ (Local DNS / Central / Hybrid)
- [ ] **Network Bottleneck Awareness**: _____________ (Documented / Not discussed)

### ✅ Hybrid Connectivity Checklist
- [ ] **Hybrid Connectivity**: _____________ (ExpressRoute / VPN / None)
- [ ] **Traffic Flow**: _____________ (All via hub / Direct spoke-to-spoke / Hybrid)
- [ ] **DNS Configuration**: _____________ (Private DNS / Hybrid DNS / Public)
- [ ] **On-Premises Integration**: _____________ (Yes / No)

---

## 📝 Ecolab ADR Example (WAF-Aligned)

**Customer**: Ecolab  
**Document**: ADR Decision Matrix – 2

### Hub Extraction from Ecolab ADR (All 5 Pillars)

**RELIABILITY (Pillar 1):**
- Availability Zones: Multi-zone (3 zones)
- Multi-Region: No (single region initially)
- Backup/Restore: Daily backups, 30-day retention, 4-hour RTO
- Disaster Recovery: Active-passive (manual failover)
- SLA Required: 99.9% uptime
- Hub Redundancy: Multiple instances across zones

**SECURITY (Pillar 2):**
- Firewall: Azure Firewall (centralized)
- Egress: Centralized outbound control for all AKS clusters
- Ingress: Application Gateway with WAF
- Identity Provider: Microsoft Entra ID
- Access Model: Azure RBAC (platform-level) + Kubernetes RBAC (workload-level)
- Private Endpoints: Centralized management (ACR, Key Vault, Storage)
- Azure Policy: Platform-scope, enforces security baseline
- Network Policies: Enabled in spokes (Cilium for L7 policies)
- Compliance: SOC2 + Data sovereignty requirements
- Privileged Access: Entra PIM (target state)

**COST OPTIMIZATION (Pillar 3):**
- VM SKU Strategy: D-series (D4s_v5, D8s_v5) - balanced compute/memory
- Commitment: Savings plan (1-year commitment, 20% discount)
- Hub Min Nodes: 3 (high availability)
- Hub Max Nodes: 10 (reserve capacity for failover)
- Cost Allocation: Chargeback per spoke based on consumption
- Reserved Capacity: 80% hub nodes, 20% spot for non-critical workloads

**OPERATIONAL EXCELLENCE (Pillar 4):**
- IaC Tool: Terraform (Azure Provider)
- GitOps: Flux v2 (GitOps for configuration)
- CI/CD Pipeline: Azure DevOps (already in place)
- Observability Backend: Log Analytics (centralized workspace)
- Monitoring: Azure Monitor + Application Insights (APM)
- Node Image Updates: Automatic via kured (weekly)
- Incident Response: PagerDuty escalation (on-call rotations)
- Disaster Recovery Drills: Monthly (automated testing)

**PERFORMANCE EFFICIENCY (Pillar 5):**
- Expected Hub Scale: 5 nodes steady-state, scale to 10 under load
- Expected Spoke Count: 15 AKS clusters (dev, staging, prod environments)
- Total Pod Density: ~5,000 pods across all spokes
- Latency SLA: <100ms for inter-service communication
- Throughput SLA: 50,000 QPS peak capacity
- Autoscaling: Min 3 / Max 10 nodes, CPU target 70%
- DNS Strategy: Local DNS cache on hub for performance

**HYBRID CONNECTIVITY:**
- Connectivity: ExpressRoute (dedicated circuit to on-premises)
- Traffic Flow: All spoke egress via hub firewall → ExpressRoute
- DNS: Private DNS zones for Azure + Hybrid DNS for on-premises
- On-Premises Integration: Yes (mission-critical workloads)

---

## ✅ Hub Variables Mapped from ADR (WAF-Aligned)

Once extracted, map customer ADR decisions to Hub Terraform variables across all 5 pillars:

```hcl
# ═══════════════════════════════════════════════════════════════════════
# RELIABILITY (Pillar 1) - Recovery & Availability
# ═══════════════════════════════════════════════════════════════════════

# From ADR Reliability section
variable "hub_availability_zones" {
  description = "Availability zones for hub components"
  default     = [1, 2, 3]  # ADR: "Multi-zone (3 zones)"
}

variable "backup_enabled" {
  description = "Enable backup/restore for hub resources"
  default     = true  # ADR: "Daily backups, 30-day retention"
}

variable "backup_retention_days" {
  default = 30  # ADR: "30-day retention"
}

variable "recovery_time_objective_hours" {
  default = 4  # ADR: "4-hour RTO"
}

variable "hub_min_nodes" {
  description = "Minimum hub nodes for redundancy"
  default     = 3  # ADR: "3 nodes for HA"
}

variable "hub_max_nodes" {
  description = "Maximum hub nodes for failover capacity"
  default     = 10  # ADR: "Reserve capacity"
}

# ═══════════════════════════════════════════════════════════════════════
# SECURITY (Pillar 2) - Protection & Compliance
# ═══════════════════════════════════════════════════════════════════════

# From ADR Security section - Egress Control
variable "enable_azure_firewall" {
  default = true  # ADR: "Azure Firewall (centralized)"
}

variable "enable_egress_restriction" {
  default = true  # ADR: "Centralized outbound control"
}

# From ADR Security section - Ingress
variable "enable_application_gateway" {
  default = true  # ADR: "Application Gateway"
}

variable "enable_waf" {
  default = true  # ADR: "Application Gateway with WAF"
}

# From ADR Security section - Identity & Access
variable "identity_provider" {
  default = "entra_id"  # ADR: "Microsoft Entra ID"
}

variable "enable_rbac" {
  default = true  # ADR: "Azure RBAC + Kubernetes RBAC"
}

variable "enable_privileged_access_management" {
  default = true  # ADR: "Entra PIM (target state)"
}

# From ADR Security section - Network Isolation
variable "enable_private_endpoints" {
  default = true  # ADR: "Centralized management"
}

variable "enable_private_dns_zones" {
  default = true  # ADR: "Private DNS Zones"
}

variable "network_policy_engine" {
  default = "cilium"  # ADR: "Cilium for L7 policies"
}

# From ADR Security section - Compliance
variable "compliance_requirements" {
  default = ["soc2", "data_sovereignty"]  # ADR: "SOC2 + Data sovereignty"
}

variable "enable_azure_policy" {
  default = true  # ADR: "Platform-scope enforcement"
}

# ═══════════════════════════════════════════════════════════════════════
# COST OPTIMIZATION (Pillar 3) - Efficient Spending
# ═══════════════════════════════════════════════════════════════════════

# From ADR Cost Optimization section
variable "compute_sku_tier" {
  default = "d_series"  # ADR: "D-series (D4s_v5, D8s_v5)"
}

variable "vm_sku_size" {
  default = "Standard_D4s_v5"  # ADR: "Balanced compute/memory"
}

variable "enable_savings_plan" {
  default = true  # ADR: "1-year commitment"
}

variable "savings_plan_commitment_percent" {
  default = 80  # ADR: "80% hub nodes reserved"
}

variable "enable_spot_instances" {
  default = true  # ADR: "20% spot for non-critical"
}

variable "spot_percentage" {
  default = 20  # ADR: "20% of nodes as spot"
}

variable "cost_allocation_model" {
  default = "chargeback_per_spoke"  # ADR: "Chargeback model"
}

# ═══════════════════════════════════════════════════════════════════════
# OPERATIONAL EXCELLENCE (Pillar 4) - Procedures & Automation
# ═══════════════════════════════════════════════════════════════════════

# From ADR Operational Excellence section
variable "iac_tool" {
  default = "terraform"  # ADR: "Terraform"
}

variable "gitops_enabled" {
  default = true  # ADR: "Flux v2"
}

variable "gitops_platform" {
  default = "flux_v2"  # ADR: "Flux v2"
}

variable "ci_cd_platform" {
  default = "azure_devops"  # ADR: "Azure DevOps"
}

variable "observability_backend" {
  default = "log_analytics"  # ADR: "Log Analytics (centralized)"
}

variable "monitoring_platform" {
  default = "azure_monitor_apm"  # ADR: "Azure Monitor + Application Insights"
}

variable "node_image_update_strategy" {
  default = "automatic_kured"  # ADR: "Automatic via kured (weekly)"
}

variable "enable_incident_response_automation" {
  default = true  # ADR: "PagerDuty escalation"
}

variable "disaster_recovery_drill_frequency" {
  default = "monthly"  # ADR: "Monthly testing"
}

# ═══════════════════════════════════════════════════════════════════════
# PERFORMANCE EFFICIENCY (Pillar 5) - Capacity & Optimization
# ═══════════════════════════════════════════════════════════════════════

# From ADR Performance Efficiency section
variable "hub_capacity_nodes_steady_state" {
  default = 5  # ADR: "5 nodes steady-state"
}

variable "hub_capacity_nodes_peak" {
  default = 10  # ADR: "Scale to 10 under load"
}

variable "expected_spoke_count" {
  default = 15  # ADR: "15 AKS clusters"
}

variable "total_pod_density" {
  default = 5000  # ADR: "~5,000 pods across spokes"
}

variable "latency_sla_ms" {
  default = 100  # ADR: "<100ms for inter-service"
}

variable "throughput_sla_qps" {
  default = 50000  # ADR: "50,000 QPS peak"
}

variable "autoscaling_cpu_target_percent" {
  default = 70  # ADR: "CPU target 70%"
}

variable "enable_local_dns_cache" {
  default = true  # ADR: "Local DNS cache for performance"
}

# ═══════════════════════════════════════════════════════════════════════
# HYBRID CONNECTIVITY (Infrastructure)
# ═══════════════════════════════════════════════════════════════════════

# From ADR Hybrid Connectivity section
variable "enable_hybrid_connectivity" {
  type        = bool
  description = "Enable hybrid connectivity (ExpressRoute or VPN) as specified in the ADR"
  default     = true  # ADR: "ExpressRoute"
}

variable "hybrid_connectivity_type" {
  type        = string
  description = "Type of hybrid connectivity (expressroute, vpn) selected in the ADR"
  default     = "expressroute"  # ADR: "ExpressRoute (dedicated circuit)"
}

variable "traffic_routing_model" {
  type        = string
  description = "Traffic routing model for spoke workloads (hub_firewall, direct) as defined in the ADR"
  default     = "hub_firewall"  # ADR: "All spoke egress via hub"
}

variable "enable_dns_hybrid" {
  type        = bool
  description = "Enable hybrid DNS integration between on-premises and Azure per ADR"
  default     = true  # ADR: "Hybrid DNS for on-premises"
}

variable "onpremises_integration_required" {
  type        = bool
  description = "Indicates if on-premises integration is required for mission-critical workloads per ADR"
  default     = true  # ADR: "Yes (mission-critical workloads)"
}
```

---

## 🔄 Pillar-to-Variable Mapping Reference

Quick reference for mapping ADR sections to Terraform variables:

| WAF Pillar | ADR Section | Terraform Variables | Example |
|-----------|-------------|-------------------|---------|
| **Reliability** | Availability Requirements | `hub_availability_zones`, `hub_min_nodes`, `backup_enabled` | "Multi-zone, 3 nodes" |
| **Security** | Firewall & Compliance | `enable_azure_firewall`, `compliance_requirements`, `enable_rbac` | "Azure Firewall + SOC2" |
| **Cost Optimization** | VM & Commitment Strategy | `vm_sku_size`, `savings_plan_commitment_percent` | "D4s_v5, 80% reserved" |
| **Operational Excellence** | IaC & GitOps | `iac_tool`, `gitops_platform`, `ci_cd_platform` | "Terraform + Flux + DevOps" |
| **Performance Efficiency** | Capacity & Autoscaling | `hub_capacity_nodes_peak`, `autoscaling_cpu_target_percent` | "10 nodes max, 70% CPU" |

---

## 🔄 ADR-to-Agent-Skills Workflow

```
1. Collect ADR from Customer
   └─ Ecolab example provided above
   
2. Extract Hub Requirements
   └─ Use checklist above
   
3. Map to Hub Variables
   └─ Follow variable mapping example
   
4. Pass to Agent Skills (Option A)
   └─ In VS Code GitHub Copilot Chat:
   └─ Say: "@workspace Generate hub infrastructure using extracted variables from the ADR"
   └─ Or reference: README.md Option A section for detailed Agent Skills workflow
   
5. Agent Skills Generates Hub Code
   └─ Using AVM modules
   └─ With values from ADR
```

---

## 📊 Real Example: Ecolab

**From ADR:**
> "**Hub Network & Connectivity**  
> - **Firewall**: Azure Firewall  
> - **Egress**: Centralized outbound control for all AKS clusters  
> - **Ingress Tier**: Azure Application Gateway with WAF"

**Extract to Agent Skills:**
```
Hub Configuration:
- Azure Firewall: ENABLED (centralized egress)
- Application Gateway: ENABLED with WAF (ingress)
- Firewall Egress Rules: Route ALL spoke traffic via hub
- Highly Available: YES (multiple zones)
```

**Agent Skills Generates:**
```hcl
module "azure_firewall" {
  source  = "Azure/avm-res-network-azurefirewall/azurerm"
  version = "~> 0.1"
  enable_telemetry = true
  # Configured for centralized egress per ADR
}

module "application_gateway" {
  source  = "Azure/avm-res-network-applicationgateway/azurerm"
  version = "~> 0.1"
  enable_telemetry = true
  enable_waf = true  # Per ADR requirement
}
```

---

## 🚨 Red Flags in ADR

Stop and ask clarifying questions if ADR contains:

| Red Flag | Question to Ask |
|----------|-----------------|
| "Hub" mentioned but no firewall defined | "Who controls egress? Should we add Azure Firewall?" |
| "Private cluster" but no private endpoint setup | "How will clients securely reach the cluster?" |
| Firewall mentioned but no routing setup | "How does traffic flow from spokes through firewall?" |
| Multiple DNS services mentioned | "Should we consolidate to private DNS?" |
| No observability mentioned | "Where should logs/metrics go? Centralized?" |

---

## 💡 Tips for ADR Extraction

1. **Read Hub section first** - Understand platform architecture
2. **Note all interconnections** - How hub connects to spokes
3. **Identify shared services** - Firewall, DNS, Log Analytics
4. **Check for compliance notes** - Any regulatory requirements?
5. **Look for governance model** - Who controls what?
6. **Map to variables systematically** - Use checklist above
7. **Validate with customer** - "Is this what you meant?"

---

## 📚 Integration with Agent Skills & Manual Workflows

**Option 1: Questionnaire** → Agent Skills (Fastest)
- Use: [customer-requirements-quick-reference.md](./customer-requirements-quick-reference.md)
- Input: 8 customer answers
- Process: Agent Skills automates everything
- Output: Ready-to-deploy infrastructure code

**Option 2: ADR (This Guide)** → Choice of two workflows
- Use: [adr-to-hub-extraction-guide.md](./adr-to-hub-extraction-guide.md) (you are here)
- Input: Customer ADR document
- Extract: Hub variables using WAF-aligned checklist
- **Choice A**: Pass extracted variables to Agent Skills (automated code generation) ⭐ RECOMMENDED
- **Choice B**: Use extracted variables in manual Option C workflow (full control)

**Both paths support infrastructure generation:**
- Agent Skills: Fully automated, fastest path
- Manual (Option C): Full control, reference your extracted variables or configurations

---

## ✅ Validation Before Generating

Before passing to SKILL.md:

- [ ] ADR has clear Hub section
- [ ] All Hub components identified
- [ ] Firewall/Egress control documented
- [ ] Ingress strategy defined
- [ ] DNS/Private Endpoints documented
- [ ] Log Analytics/Monitoring identified
- [ ] Identity provider documented
- [ ] No contradictions between components
- [ ] Customer has approved extracted requirements

---

## 🎯 Next Steps

1. **Extract Hub variables** from ADR using checklist above
2. **Map to Terraform variables** using example mapping section
3. **Choose your workflow:**
   - **Option A (Recommended)**: Pass extracted variables to Agent Skills for automated code generation
   - **Option C**: Use extracted variables in manual workflow for full control
4. **Code generates automatically** via Agent Skills OR manually with Option C (your choice)

**Ready?** Have the ADR ready and follow the extraction checklist above.
