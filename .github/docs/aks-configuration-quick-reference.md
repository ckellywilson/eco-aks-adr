# AKS Configuration Quick Reference

This is a condensed reference for quick lookups. For detailed guidance, see [aks-configuration-decisions.md](aks-configuration-decisions.md).

---

## Microsoft Recommended Production Configuration

```hcl
# Network Plugin: Azure CNI Overlay
network_plugin      = "azure"
network_plugin_mode = "overlay"
pod_cidr            = "192.168.0.0/16"

# Data Plane: Cilium (eBPF)
network_dataplane   = "cilium"

# Network Policy: Cilium (built-in)
network_policy      = "cilium"

# Outbound Type: User Defined Routing (for egress restriction)
outbound_type       = "userDefinedRouting"

# Security: Egress Restricted
enable_egress_restriction = true
egress_security_level     = "strict"
```

**Why this configuration?**
- ✅ IP efficient (overlay network)
- ✅ High performance (eBPF)
- ✅ Advanced security (L7 policies, FQDN filtering)
- ✅ Egress restriction ready
- ✅ Scalable (5,000 nodes)

---

## Configuration Options Matrix

### Network Plugin

| Option | IP Source | Max Pods/Node | Max Nodes | Use Case |
|--------|-----------|---------------|-----------|----------|
| **Azure CNI Overlay** ⭐ | Overlay (192.168.0.0/16) | 250 (110 typical) | 5,000 | **Most scenarios** |
| Azure CNI Standard | VNet subnet | 250 (30 typical) | 400 | Pods need direct VNet IPs |

### Data Plane

| Option | Technology | Performance | Network Policy | Use Case |
|--------|-----------|-------------|----------------|----------|
| **Cilium** ⭐ | eBPF | High | Built-in (L3-L7) | **Production recommended** |
| IPTables | IPTables | Standard | Separate install | Legacy/Windows nodes |

### Network Policy Engine

| Engine | Policy Layers | FQDN Filtering | Windows Support | Recommendation |
|--------|---------------|----------------|-----------------|----------------|
| **Cilium** | L3, L4, **L7** | ✅ Yes | ❌ No | ⭐ **Use this** |
| Azure NPM | L3, L4 | ❌ No | ✅ Yes | Legacy |
| Calico | L3, L4 | ❌ No | ✅ Yes | If need Windows |

### Outbound Type

| Type | Egress Path | Egress Restriction | Use Case |
|------|-------------|-------------------|----------|
| **userDefinedRouting** | Azure Firewall | ✅ Yes | **Production with compliance** |
| loadBalancer | Load Balancer + Public IP | ❌ No | Dev/test |
| managedNATGateway | NAT Gateway | ❌ No | High outbound volume |

---

## Common Configuration Patterns

### Pattern 1: Production - Egress Restricted (Scenario 2B) ⭐ RECOMMENDED

**Use Case:** Regulated industries, compliance requirements, production workloads

```hcl
network_plugin              = "azure"
network_plugin_mode         = "overlay"
network_dataplane           = "cilium"
network_policy              = "cilium"
outbound_type               = "userDefinedRouting"
enable_egress_restriction   = true
```

**Example:** [prod-egress-restricted.tfvars](../examples/prod-egress-restricted.tfvars)

---

### Pattern 2: Development - Standard Security

**Use Case:** Development, testing, rapid iteration

```hcl
network_plugin              = "azure"
network_plugin_mode         = "overlay"
network_dataplane           = "cilium"
network_policy              = "cilium"
outbound_type               = "loadBalancer"
enable_egress_restriction   = false
```

**Example:** [dev-standard.tfvars](../examples/dev-standard.tfvars)

---

### Pattern 3: Production - Direct Pod IPs

**Use Case:** Pods must be directly routable from VNet (legacy compatibility)

```hcl
network_plugin              = "azure"
network_plugin_mode         = null  # Standard CNI
network_dataplane           = "cilium"
network_policy              = "cilium"
outbound_type               = "userDefinedRouting"
enable_egress_restriction   = true
```

**Example:** [prod-standard-cni.tfvars](../examples/prod-standard-cni.tfvars)

---

## Compatibility Matrix

### Network Plugin + Data Plane

| Network Plugin | Cilium | IPTables |
|---------------|--------|----------|
| Azure CNI Overlay | ✅ Yes | ✅ Yes |
| Azure CNI Standard | ✅ Yes | ✅ Yes |

### Data Plane + Network Policy

| Data Plane | Cilium Policy | Azure NPM | Calico |
|-----------|---------------|-----------|--------|
| Cilium | ✅ Built-in | ❌ No | ❌ No |
| IPTables | ❌ No | ✅ Yes | ✅ Yes |

### Outbound Type + Egress Restriction

| Outbound Type | Supports Egress Restriction |
|--------------|---------------------------|
| userDefinedRouting | ✅ Yes (required for egress restriction) |
| loadBalancer | ❌ No |
| managedNATGateway | ❌ No |
| userAssignedNATGateway | ❌ No |

---

## Decision Tree (Quick)

```
START: What's your primary requirement?

┌─ Need egress restriction? (compliance/security)
│  └─> Use: Azure CNI Overlay + Cilium + userDefinedRouting
│       Example: prod-egress-restricted.tfvars
│
┌─ Need direct pod IPs from VNet?
│  └─> Use: Azure CNI Standard + Cilium + userDefinedRouting
│       Example: prod-standard-cni.tfvars
│
└─ Development/testing?
   └─> Use: Azure CNI Overlay + Cilium + loadBalancer
       Example: dev-standard.tfvars
```

---

## Azure CLI Examples

### Create Cluster with Microsoft Recommended Config

```bash
az aks create \
  --name myAKSCluster \
  --resource-group myResourceGroup \
  --location eastus \
  --network-plugin azure \
  --network-plugin-mode overlay \
  --network-dataplane cilium \
  --pod-cidr 192.168.0.0/16 \
  --outbound-type userDefinedRouting \
  --generate-ssh-keys
```

### Verify Configuration

```bash
# Check network plugin
az aks show -g myResourceGroup -n myAKSCluster \
  --query "networkProfile.networkPlugin"

# Check data plane
az aks show -g myResourceGroup -n myAKSCluster \
  --query "networkProfile.networkDataplane"

# Check outbound type
az aks show -g myResourceGroup -n myAKSCluster \
  --query "networkProfile.outboundType"
```

---

## Terraform Variable Quick Reference

### Required Variables

```hcl
variable "network_plugin" {
  type        = string
  description = "Network plugin: 'azure'"
  validation {
    condition     = var.network_plugin == "azure"
    error_message = "Only 'azure' is supported"
  }
}

variable "network_plugin_mode" {
  type        = string
  description = "'overlay' for Azure CNI Overlay, null for standard"
  validation {
    condition     = var.network_plugin_mode == null || var.network_plugin_mode == "overlay"
    error_message = "Must be 'overlay' or null"
  }
}

variable "network_dataplane" {
  type        = string
  description = "'cilium' (recommended) or null for IPTables"
  validation {
    condition     = var.network_dataplane == null || var.network_dataplane == "cilium"
    error_message = "Must be 'cilium' or null"
  }
}

variable "network_policy" {
  type        = string
  description = "'cilium', 'azure', 'calico', or null"
  validation {
    condition     = contains(["cilium", "azure", "calico", null], var.network_policy)
    error_message = "Must be 'cilium', 'azure', 'calico', or null"
  }
}

variable "outbound_type" {
  type        = string
  description = "'userDefinedRouting', 'loadBalancer', 'managedNATGateway'"
  validation {
    condition     = contains(["userDefinedRouting", "loadBalancer", "managedNATGateway", "userAssignedNATGateway"], var.outbound_type)
    error_message = "Invalid outbound type"
  }
}
```

---

## Additional Resources

- **Detailed Decision Guide:** [aks-configuration-decisions.md](aks-configuration-decisions.md)
- **Deployment Scenarios:** [deployment-scenarios.md](deployment-scenarios.md)
- **Example Configurations:** [../examples/](../examples/)
- **Official MS Docs:** [Azure CNI Powered by Cilium](https://learn.microsoft.com/azure/aks/azure-cni-powered-by-cilium)
