# Example: Production Environment - Standard Azure CNI (Direct Pod IPs)
# Use Case: Production requiring direct pod IP routable from VNet

# ============================================================================
# DEPLOYMENT MODEL: Platform-Provided Networking (Scenario 2)
# ============================================================================
create_resource_group   = false
create_virtual_network  = false
create_vnet_peering     = false
create_route_table      = false

existing_resource_group_name        = "rg-spoke-aks-prod"
existing_virtual_network_name       = "vnet-spoke-aks-prod"
existing_aks_system_subnet_name     = "snet-aks-system"
existing_aks_user_subnet_name       = "snet-aks-user"
existing_private_endpoint_subnet_name = "snet-private-endpoints"

# ============================================================================
# NETWORK PLUGIN: Azure CNI Standard (Direct VNet IPs for pods)
# ============================================================================
network_plugin          = "azure"
network_plugin_mode     = null  # Standard CNI (not overlay)
# pod_cidr is NOT used - pods get IPs from VNet subnets

# ============================================================================
# DATA PLANE: Azure CNI Powered by Cilium (Microsoft Recommended)
# ============================================================================
network_dataplane       = "cilium"

# ============================================================================
# NETWORK POLICY: Cilium (Built-in with Cilium data plane)
# ============================================================================
network_policy          = "cilium"

# ============================================================================
# OUTBOUND TYPE: User Defined Routing (For egress restriction)
# ============================================================================
outbound_type           = "userDefinedRouting"

# ============================================================================
# SECURITY POSTURE: Egress Restricted
# ============================================================================
enable_egress_restriction = true
egress_security_level     = "strict"

azure_firewall_private_ip = "10.0.1.4"

# ============================================================================
# CLUSTER CONFIGURATION
# ============================================================================
environment             = "prod"
location                = "eastus"

kubernetes_version      = "1.29"
sku_tier                = "Standard"

# ============================================================================
# NODE POOLS
# ============================================================================
system_node_pool = {
  name                = "system"
  vm_size             = "Standard_D8s_v5"
  node_count          = 3
  availability_zones  = ["1", "2", "3"]
  max_pods            = 30  # Lower with standard CNI due to IP consumption
  os_disk_type        = "Ephemeral"
}

user_node_pool = {
  name                = "workload"
  vm_size             = "Standard_D8s_v5"
  node_count          = 5
  min_count           = 3
  max_count           = 15  # Lower max due to IP constraints
  enable_auto_scaling = true
  availability_zones  = ["1", "2", "3"]
  max_pods            = 30  # Adjust based on IP availability
  os_disk_type        = "Ephemeral"
}

# ============================================================================
# ADVANCED FEATURES
# ============================================================================
enable_advanced_container_networking_services = true
enable_azure_policy                           = true
enable_microsoft_defender                     = true
enable_oms_agent                              = true
enable_private_cluster                        = true

# ============================================================================
# TAGS
# ============================================================================
tags = {
  Environment = "prod"
  ManagedBy   = "Terraform"
  Project     = "AKS-LZ"
  NetworkMode = "StandardCNI"
}
