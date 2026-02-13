variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region for deployment"
  type        = string
  default     = "eastus2"
}

variable "location_code" {
  description = "Short code for location"
  type        = string
  default     = "eus2"
}

variable "resource_group_name" {
  description = "Name of the spoke resource group"
  type        = string
}

variable "spoke_vnet_address_space" {
  description = "Spoke VNet address space"
  type        = list(string)
  default     = ["10.1.0.0/16"]
}

variable "aks_cluster_name" {
  description = "AKS cluster name"
  type        = string
  default     = "aks-eco-prod-eus2"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.30"
}

variable "aks_sku_tier" {
  description = "AKS SKU tier (Free, Standard, Premium)"
  type        = string
  default     = "Standard"
}

variable "aks_network_plugin" {
  description = "Network plugin (azure, kubenet)"
  type        = string
  default     = "azure"
}

variable "aks_network_policy" {
  description = "Network policy (azure, calico, cilium)"
  type        = string
  default     = "cilium"
}

variable "aks_pod_cidr" {
  description = "Pod CIDR range"
  type        = string
  default     = "192.168.0.0/16"
}

variable "aks_service_cidr" {
  description = "Service CIDR range"
  type        = string
  default     = "172.16.0.0/16"
}

variable "aks_dns_service_ip" {
  description = "DNS service IP"
  type        = string
  default     = "172.16.0.10"
}

variable "system_node_pool_size" {
  description = "System node pool VM size"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "system_node_pool_count" {
  description = "System node pool node count"
  type        = number
  default     = 2
}

variable "user_node_pool_size" {
  description = "User node pool VM size"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "user_node_pool_count" {
  description = "User node pool node count"
  type        = number
  default     = 2
}

variable "enable_private_cluster" {
  description = "Enable private AKS cluster"
  type        = bool
  default     = true
}

variable "enable_managed_identity" {
  description = "Use managed identity for AKS"
  type        = bool
  default     = true
}

variable "enable_azure_policy" {
  description = "Enable Azure Policy add-on"
  type        = bool
  default     = true
}

variable "enable_workload_identity" {
  description = "Enable Workload Identity"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable Container Insights monitoring"
  type        = bool
  default     = true
}

variable "enable_web_app_routing" {
  description = "Enable the Azure-managed NGINX ingress controller (Web App Routing add-on)"
  type        = bool
  default     = false
}

variable "web_app_routing_dns_zone_ids" {
  description = "List of Azure DNS zone IDs for Web App Routing add-on to manage DNS records. Leave empty for no DNS integration."
  type        = list(string)
  default     = []
}

variable "nginx_internal_lb_ip" {
  description = "Static internal IP address for NGINX ingress controller load balancer. Must be from AKS nodes subnet range."
  type        = string
  default     = "10.1.0.50"

  validation {
    condition     = can(regex("^10\\.1\\.[0-3]\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])$", var.nginx_internal_lb_ip))
    error_message = "The nginx_internal_lb_ip must be a valid IPv4 address within the AKS nodes subnet range 10.1.0.0/22."
  }
}

variable "hub_resource_group_name" {
  description = "Hub resource group name for data source"
  type        = string
}

variable "hub_name" {
  description = "Hub name (for reading outputs)"
  type        = string
  default     = "hub"
}

variable "custom_dns_servers" {
  description = "Custom DNS servers (fallback if hub outputs not available)"
  type        = list(string)
  default     = []
}

variable "admin_username" {
  description = "Admin username for jump box VMs"
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  description = "SSH public key for jump box VM authentication"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "prod"
    ManagedBy   = "Terraform"
    Purpose     = "AKS Spoke - Production"
  }
}
