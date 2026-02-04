# Example: Production Environment - Egress Restricted (Scenario 2B) ⭐ RECOMMENDED
# Use Case: Enterprise production with platform-provided networking and strict egress control

# ============================================================================
# DEPLOYMENT MODEL: Platform-Provided Networking (Scenario 2)
# ============================================================================
create_resource_group   = false  # Platform team provides
create_virtual_network  = false  # Platform team provides
create_vnet_peering     = false  # Platform team provides
create_route_table      = false  # Platform team provides

# Reference existing platform-provided resources
existing_resource_group_name        = "rg-spoke-aks-prod"
existing_virtual_network_name       = "vnet-spoke-aks-prod"
existing_aks_system_subnet_name     = "snet-aks-system"
existing_aks_user_subnet_name       = "snet-aks-user"
existing_private_endpoint_subnet_name = "snet-private-endpoints"

# ============================================================================
# NETWORK PLUGIN: Azure CNI Overlay (Microsoft Recommended)
# ============================================================================
network_plugin          = "azure"
network_plugin_mode     = "overlay"
pod_cidr                = "192.168.0.0/16"

# ============================================================================
# DATA PLANE: Azure CNI Powered by Cilium (Microsoft Recommended for Production)
# ============================================================================
network_dataplane       = "cilium"

# ============================================================================
# NETWORK POLICY: Cilium (Built-in with Cilium data plane)
# ============================================================================
network_policy          = "cilium"

# ============================================================================
# OUTBOUND TYPE: User Defined Routing (REQUIRED for egress restriction)
# ============================================================================
outbound_type           = "userDefinedRouting"

# ============================================================================
# SECURITY POSTURE: Egress Restricted (Force tunnel via Azure Firewall)
# ============================================================================
enable_egress_restriction = true
egress_security_level     = "strict"

# Hub Azure Firewall IP (for UDR next hop)
azure_firewall_private_ip = "10.0.1.4"

# ============================================================================
# CLUSTER CONFIGURATION
# ============================================================================
environment             = "prod"
location                = "eastus"

kubernetes_version      = "1.29"  # Use LTS version
sku_tier                = "Standard"  # Standard tier for production SLA

# ============================================================================
# NODE POOLS (Production-sized)
# ============================================================================
system_node_pool = {
  name                = "system"
  vm_size             = "Standard_D8s_v5"
  node_count          = 3
  availability_zones  = ["1", "2", "3"]
  max_pods            = 110  # Higher with overlay
  os_disk_type        = "Ephemeral"  # Better performance
}

user_node_pool = {
  name                = "workload"
  vm_size             = "Standard_D8s_v5"
  node_count          = 5
  min_count           = 3
  max_count           = 20
  enable_auto_scaling = true
  availability_zones  = ["1", "2", "3"]
  max_pods            = 110
  os_disk_type        = "Ephemeral"
}

# ============================================================================
# ADVANCED FEATURES (Production)
# ============================================================================
enable_advanced_container_networking_services = true  # For Cilium L7 policies, FQDN filtering
enable_azure_policy                           = true
enable_microsoft_defender                     = true
enable_oms_agent                              = true

# Private cluster (production security)
enable_private_cluster                        = true
private_dns_zone_id                           = "/subscriptions/.../privateDnsZones/privatelink.eastus.azmk8s.io"

# ============================================================================
# MONITORING & LOGGING
# ============================================================================
log_analytics_workspace_id = "/subscriptions/.../workspaces/law-aks-prod"

# ============================================================================
# TAGS
# ============================================================================
tags = {
  Environment = "prod"
  ManagedBy   = "Terraform"
  Project     = "AKS-LZ"
  CostCenter  = "Platform"
  Compliance  = "PCI-DSS"
  DataClassification = "Confidential"
}
