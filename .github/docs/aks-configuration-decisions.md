# AKS Network Configuration Decision Guide

⚠️ **COMPLETE THIS GUIDE BEFORE GENERATING INFRASTRUCTURE CODE**

This guide helps you select the correct AKS network configuration based on official Microsoft recommendations and your specific requirements.

---

## Decision Checklist

**STATUS:** [ ] Not Started → [ ] In Progress → [ ] Complete

Complete **ALL** sections below before opening `.github/prompts/spoke-aks.prompt.md`

---

## 1. Network Plugin Selection (REQUIRED)

Choose how pod IP addresses are assigned. **Microsoft recommends Azure CNI Overlay for most scenarios.**

### Option A: Azure CNI Overlay ⭐ **MICROSOFT RECOMMENDED**

**When to Use:**
- Most production and development scenarios
- IP address conservation is important
- Need to scale to large clusters (up to 5,000 nodes)
- Pods don't need to be directly routable from outside the cluster

**Characteristics:**
- Pods get IPs from overlay network (e.g., 192.168.0.0/16)
- **10x more pods per node** than standard CNI
- Egress traffic is SNAT'd to node IP
- Maximum 5,000 nodes, 250 pods/node
- Low IP consumption from VNet address space

**Terraform Configuration:**
```hcl
network_plugin      = "azure"
network_plugin_mode = "overlay"
pod_cidr            = "192.168.0.0/16"
```

**Select this option:** [ ]

---

### Option B: Azure CNI (Standard/Node Subnet)

**When to Use:**
- Pods need direct VNet IP addresses (routable from VNet)
- Integration with existing network security controls that require pod IPs
- Compliance requirements mandate direct pod IP visibility

**Characteristics:**
- Pods get IP addresses from VNet subnet
- High IP consumption (1 IP per pod)
- Maximum 64,000 IPs per cluster
- Direct pod connectivity from VNet

**Terraform Configuration:**
```hcl
network_plugin      = "azure"
network_plugin_mode = null
# No pod_cidr needed - uses VNet IPs
```

**Select this option:** [ ]

---

### Option C: Azure CNI with Dynamic Pod IP Allocation

**When to Use:**
- Need direct pod IPs but want more efficient IP usage
- Can plan dedicated pod subnet

**Characteristics:**
- Pods get IPs from dedicated subnet with dynamic allocation
- More efficient than standard CNI
- Maximum 64,000 IPs
- Requires pod subnet configuration

**Terraform Configuration:**
```hcl
network_plugin      = "azure"
network_plugin_mode = null
# Configure pod_subnet_id in AKS module
```

**Select this option:** [ ]

---

**MY NETWORK PLUGIN SELECTION:** `_______________________________`

---

## 2. Network Data Plane Selection (REQUIRED)

Choose the data plane technology. **Microsoft recommends Azure CNI Powered by Cilium for production.**

### Option A: Azure CNI Powered by Cilium ⭐ **MICROSOFT RECOMMENDED**

**When to Use:**
- **All production environments**
- Need high performance (eBPF-based)
- Want advanced network policies (L3-L7)
- Need FQDN-based filtering
- Egress restriction scenarios

**Benefits:**
- ✅ eBPF kernel-level performance (no IPTables)
- ✅ Built-in network policy engine (no separate install)
- ✅ Support for L7 network policies
- ✅ FQDN filtering with Advanced Container Networking Services
- ✅ Better observability
- ✅ Larger cluster support

**Limitations:**
- Linux only (no Windows node pools)

**Terraform Configuration:**
```hcl
network_dataplane = "cilium"
network_policy    = "cilium"  # Built-in, no separate install
```

**Compatible with:** Azure CNI Overlay ✅ | Azure CNI Standard ✅

**Select this option:** [ ]

---

### Option B: Azure IPTables (Legacy)

**When to Use:**
- Need Windows node pools
- Legacy compatibility requirements
- Cannot use Cilium for specific reasons

**Characteristics:**
- IPTables-based (traditional approach)
- Requires separate network policy engine installation
- Standard performance

**Terraform Configuration:**
```hcl
network_dataplane = null  # or omit (uses default)
network_policy    = "azure"  # or "calico"
```

**Select this option:** [ ]

---

**MY DATA PLANE SELECTION:** `_______________________________`

---

## 3. Network Policy Engine Selection (REQUIRED)

Choose how network policies are enforced. **If using Cilium data plane, this is automatically set to Cilium.**

### Option A: Cilium ⭐ **MICROSOFT RECOMMENDED**

**When to Use:**
- Using Azure CNI Powered by Cilium data plane (automatic)
- Need advanced network policies (L7, FQDN filtering)
- Production environments

**Benefits:**
- ✅ Built-in (no extra installation)
- ✅ L3, L4, **and L7** network policies
- ✅ FQDN-based filtering
- ✅ eBPF performance
- ✅ Better scalability with identity-based policies

**Terraform Configuration:**
```hcl
network_policy = "cilium"  # Required when network_dataplane = "cilium"
```

**Select this option:** [ ]

---

### Option B: Azure Network Policy Manager (Azure NPM)

**When to Use:**
- Using Azure IPTables data plane
- Need Windows node pool support
- Basic L3/L4 policies sufficient

**Characteristics:**
- Azure-native
- IPTables-based
- L3 and L4 policies only
- **Not recommended** by Microsoft (legacy)

**Terraform Configuration:**
```hcl
network_policy = "azure"
```

**Select this option:** [ ]

---

### Option C: Calico

**When to Use:**
- Using Azure IPTables data plane
- Need richer features than Azure NPM
- Windows node pool support needed

**Characteristics:**
- Open-source (Tigera)
- IPTables-based
- L3 and L4 policies
- Rich feature set

**Terraform Configuration:**
```hcl
network_policy = "calico"
```

**Select this option:** [ ]

---

### Option D: None

**When to Use:**
- Development/testing only
- No network isolation required

**Terraform Configuration:**
```hcl
network_policy = null
```

**Select this option:** [ ]

---

**MY NETWORK POLICY SELECTION:** `_______________________________`

---

## 4. Outbound Type (Egress) Selection (REQUIRED)

Choose how cluster traffic egresses to the internet. **For egress restriction scenarios, use userDefinedRouting.**

### Option A: userDefinedRouting ⭐ **REQUIRED FOR EGRESS RESTRICTION**

**When to Use:**
- **Egress restriction scenarios (Scenario 2B, 4)**
- Compliance requirements mandate traffic inspection
- Need centralized egress control via Azure Firewall
- Zero-trust networking

**How it Works:**
- Route table with `0.0.0.0/0 → Azure Firewall` forces all egress traffic through firewall
- No public IP assigned to AKS load balancer
- All internet-bound traffic inspected by Azure Firewall

**Requirements:**
- ✅ Route table with default route configured
- ✅ Azure Firewall allow rules for AKS requirements
- ✅ NSGs configured to deny direct internet access

**Terraform Configuration:**
```hcl
outbound_type = "userDefinedRouting"
```

**Select this option:** [ ]

---

### Option B: loadBalancer (Default)

**When to Use:**
- Standard deployments without egress restriction
- Development/testing environments
- No compliance requirements for traffic inspection

**How it Works:**
- Azure Load Balancer with public IP for egress
- Direct internet access from cluster
- Fixed SNAT ports per node

**Terraform Configuration:**
```hcl
outbound_type = "loadBalancer"
```

**Select this option:** [ ]

---

### Option C: managedNATGateway

**When to Use:**
- High volume of outbound connections
- SNAT port exhaustion with load balancer
- No egress restriction required

**Terraform Configuration:**
```hcl
outbound_type = "managedNATGateway"
```

**Select this option:** [ ]

---

### Option D: userAssignedNATGateway

**When to Use:**
- BYO NAT Gateway scenario
- Custom NAT requirements

**Terraform Configuration:**
```hcl
outbound_type = "userAssignedNATGateway"
```

**Select this option:** [ ]

---

**MY OUTBOUND TYPE SELECTION:** `_______________________________`

---

## 5. Security Posture Selection (REQUIRED)

Choose the overall security configuration. Maps to deployment scenario variants.

### Variant A: Standard Security

**Characteristics:**
- Basic NSG rules
- Permissive egress (direct internet access)
- Suitable for dev/test

**Variables:**
```hcl
enable_egress_restriction = false
egress_security_level     = "standard"
outbound_type            = "loadBalancer"
```

**Select this option:** [ ]

---

### Variant B: Egress-Restricted Security ⭐ **RECOMMENDED FOR PRODUCTION**

**Characteristics:**
- Force tunnel all traffic through Azure Firewall
- Restrictive NSGs (deny direct internet)
- Deny-by-default firewall rules
- Compliance-ready

**Variables:**
```hcl
enable_egress_restriction = true
egress_security_level     = "strict"
outbound_type            = "userDefinedRouting"
```

**Select this option:** [ ]

---

**MY SECURITY POSTURE SELECTION:** `_______________________________`

---

## 6. Configuration Summary

Once all decisions are complete, copy this configuration summary:

### Microsoft Recommended Production Configuration ⭐

```hcl
# Network Plugin
network_plugin      = "azure"
network_plugin_mode = "overlay"
pod_cidr            = "192.168.0.0/16"

# Data Plane & Network Policy
network_dataplane   = "cilium"
network_policy      = "cilium"

# Outbound Type (Egress)
outbound_type       = "userDefinedRouting"

# Security Posture
enable_egress_restriction = true
egress_security_level     = "strict"
```

### My Configuration

```hcl
# Network Plugin
network_plugin      = "[YOUR SELECTION]"
network_plugin_mode = "[YOUR SELECTION]"
pod_cidr            = "[YOUR SELECTION if overlay]"

# Data Plane & Network Policy
network_dataplane   = "[YOUR SELECTION]"
network_policy      = "[YOUR SELECTION]"

# Outbound Type (Egress)
outbound_type       = "[YOUR SELECTION]"

# Security Posture
enable_egress_restriction = [true/false]
egress_security_level     = "[standard/strict]"
```

---

## Next Steps

✅ **Step 1:** Mark this checklist as **[X] Complete** at the top

✅ **Step 2:** Open `.github/prompts/spoke-aks.prompt.md`

✅ **Step 3:** Replace all `[DECISION REQUIRED]` placeholders with your selections

✅ **Step 4:** Ask Copilot: "Implement this prompt with my configuration decisions"

---

## Reference: Configuration Compatibility Matrix

| Network Plugin | Compatible Data Planes | Compatible Outbound Types |
|---------------|----------------------|-------------------------|
| Azure CNI Overlay | Cilium ✅, IPTables ✅ | All ✅ |
| Azure CNI Standard | Cilium ✅, IPTables ✅ | All ✅ |

| Data Plane | Requires Network Policy | Supports Windows Nodes |
|-----------|------------------------|----------------------|
| Cilium | Cilium (built-in) | ❌ No |
| IPTables | Azure NPM, Calico, or None | ✅ Yes |

| Outbound Type | Egress Restriction | Requires UDR |
|--------------|-------------------|-------------|
| userDefinedRouting | ✅ Yes | ✅ Yes (0.0.0.0/0 → Firewall) |
| loadBalancer | ❌ No | ❌ No |
| managedNATGateway | ❌ No | ❌ No |
| userAssignedNATGateway | ❌ No | ❌ No |

---

## Official Microsoft Documentation References

- [Azure CNI Powered by Cilium](https://learn.microsoft.com/azure/aks/azure-cni-powered-by-cilium)
- [Azure CNI Overlay](https://learn.microsoft.com/azure/aks/concepts-network-azure-cni-overlay)
- [Network Policy Best Practices](https://learn.microsoft.com/azure/aks/network-policy-best-practices)
- [Outbound Types](https://learn.microsoft.com/azure/aks/egress-outboundtype)
- [Plan Pod Networking](https://learn.microsoft.com/azure/aks/plan-pod-networking)
- [AKS Baseline Architecture](https://learn.microsoft.com/azure/architecture/reference-architectures/containers/aks/baseline-aks)
