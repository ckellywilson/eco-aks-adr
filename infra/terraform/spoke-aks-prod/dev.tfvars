subscription_id          = "f8a5f387-2f0b-42f5-b71f-5ee02b8967cf"
environment              = "dev"
location                 = "eastus2"
location_code            = "eus2"
resource_group_name      = "rg-aks-eus2-dev"
spoke_vnet_address_space = ["10.1.0.0/16"]
aks_cluster_name         = "aks-eco-dev-eus2"
kubernetes_version       = "1.30"
aks_sku_tier             = "Standard"
aks_network_plugin       = "azure"
aks_network_policy       = "cilium"
aks_pod_cidr             = "192.168.0.0/16"
aks_service_cidr         = "172.16.0.0/16"
aks_dns_service_ip       = "172.16.0.10"
system_node_pool_size    = "Standard_D4s_v3"
system_node_pool_count   = 2
user_node_pool_size      = "Standard_D4s_v3"
user_node_pool_count     = 2
enable_private_cluster   = true
enable_managed_identity  = true
enable_azure_policy      = true
enable_workload_identity = true
enable_monitoring        = true
hub_resource_group_name  = "rg-hub-eus2-prod"
hub_name                 = "hub-eastus"

tags = {
  Environment = "dev"
  ManagedBy   = "Terraform"
  Purpose     = "AKS Spoke - Dev"
}
# NOTE: Do not commit real or placeholder SSH keys. Override this locally in an untracked *.tfvars file.
admin_ssh_public_key = ""
