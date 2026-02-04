# Example: Development Environment - Standard Security (Scenario 1A)
# Use Case: Dev/test with full team autonomy, permissive egress for development velocity

# ============================================================================
# DEPLOYMENT MODEL: Full Application Team Autonomy (Scenario 1)
# ============================================================================
create_resource_group   = true
create_virtual_network  = true
create_vnet_peering     = true
create_route_table      = false  # No forced routing in dev

# ============================================================================
# NETWORK PLUGIN: Azure CNI Overlay (Microsoft Recommended)
# ============================================================================
network_plugin          = "azure"
network_plugin_mode     = "overlay"
pod_cidr                = "192.168.0.0/16"

# ============================================================================
# DATA PLANE: Azure CNI Powered by Cilium (Microsoft Recommended)
# ============================================================================
network_dataplane       = "cilium"

# ============================================================================
# NETWORK POLICY: Cilium (Built-in with Cilium data plane)
# ============================================================================
network_policy          = "cilium"

# ============================================================================
# OUTBOUND TYPE: Load Balancer (Standard for dev/test)
# ============================================================================
outbound_type           = "loadBalancer"

# ============================================================================
# SECURITY POSTURE: Standard (Permissive)
# ============================================================================
enable_egress_restriction = false
egress_security_level     = "standard"

# ============================================================================
# CLUSTER CONFIGURATION
# ============================================================================
environment             = "dev"
location                = "eastus"
spoke_vnet_address_space = ["10.1.0.0/16"]

aks_system_subnet_cidr  = "10.1.0.0/24"
aks_user_subnet_cidr    = "10.1.1.0/23"
private_endpoint_subnet_cidr = "10.1.3.0/27"

kubernetes_version      = "1.29"  # Use LTS version
sku_tier                = "Free"  # Standard for production

# ============================================================================
# NODE POOLS
# ============================================================================
system_node_pool = {
  name                = "system"
  vm_size             = "Standard_D4s_v5"
  node_count          = 3
  availability_zones  = ["1", "2", "3"]
  max_pods            = 110  # Higher with overlay
}

user_node_pool = {
  name                = "workload"
  vm_size             = "Standard_D4s_v5"
  node_count          = 3
  availability_zones  = ["1", "2", "3"]
  max_pods            = 110
}

# ============================================================================
# ADVANCED FEATURES (Optional)
# ============================================================================
enable_advanced_container_networking_services = true  # For Cilium L7 policies, FQDN filtering

# ============================================================================
# TAGS
# ============================================================================
tags = {
  Environment = "dev"
  ManagedBy   = "Terraform"
  Project     = "AKS-LZ"
  CostCenter  = "Engineering"
}
