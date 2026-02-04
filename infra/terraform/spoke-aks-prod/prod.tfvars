# NOTE: Do not commit real subscription IDs. Provide the value via TF_VAR_subscription_id
# or a separate, git-ignored .tfvars file (e.g., prod.secrets.tfvars).
subscription_id          = "YOUR-SUBSCRIPTION-ID"
environment              = "prod"
location                 = "eastus2"
location_code            = "eus2"
resource_group_name      = "rg-aks-eus2-prod"
spoke_vnet_address_space = ["10.1.0.0/16"]
aks_cluster_name         = "aks-eco-prod-eus2"
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
  Environment = "prod"
  ManagedBy   = "Terraform"
  Purpose     = "AKS Spoke - Production"
}
# NOTE: Do not commit real SSH keys. Provide the actual admin_ssh_public_key via a non-committed tfvars file (e.g. prod.tfvars) or another secure mechanism.
admin_ssh_public_key = ""
