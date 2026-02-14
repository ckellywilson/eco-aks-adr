# Spoke AKS Production Environment Variables
subscription_id = "f8a5f387-2f0b-42f5-b71f-5ee02b8967cf"

environment   = "prod"
location      = "eastus2"
location_code = "eus2"

# Hub-managed spoke key (must match key in hub's spoke_vnets map)
spoke_key = "spoke-aks-prod"

# AKS Cluster configuration
aks_cluster_name   = "aks-eco-prod-eus2"
kubernetes_version = "1.33"
aks_sku_tier       = "Standard"

# AKS Networking
aks_network_plugin = "azure"
aks_network_policy = "cilium"
aks_pod_cidr       = "192.168.0.0/16"
aks_service_cidr   = "172.16.0.0/16"
aks_dns_service_ip = "172.16.0.10"

# Node pools
system_node_pool_size  = "Standard_D4s_v3"
system_node_pool_count = 2
user_node_pool_size    = "Standard_D4s_v3"
user_node_pool_count   = 2

# Security features
enable_private_cluster   = true
enable_managed_identity  = true
enable_azure_policy      = true
enable_workload_identity = true

# Monitoring and integrations
enable_monitoring      = true
enable_web_app_routing = true

# Internal load balancer IP
nginx_internal_lb_ip = "10.1.0.50"

# SSH public key for VM access
# Passed via ADO pipeline secret variable (ADMIN_SSH_PUBLIC_KEY)
# admin_ssh_public_key = "<set via pipeline>"

# Resource tags
tags = {
  Environment = "prod"
  ManagedBy   = "Terraform"
  Purpose     = "AKS Spoke - Production"
}
