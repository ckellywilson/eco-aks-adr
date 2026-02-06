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
  description = "Short code for location (e.g., eus2 for eastus2)"
  type        = string
  default     = "eus2"
}

variable "resource_group_name" {
  description = "Name of the hub resource group"
  type        = string
  default     = "rg-hub-eus2-dev"
}

variable "hub_vnet_address_space" {
  description = "Hub VNet address space"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "deploy_firewall" {
  description = "Deploy Azure Firewall"
  type        = bool
  default     = true
}

variable "deploy_bastion" {
  description = "Deploy Azure Bastion"
  type        = bool
  default     = true
}

variable "deploy_application_gateway" {
  description = "Deploy Application Gateway for ingress"
  type        = bool
  default     = true
}

variable "deploy_dns_resolver" {
  description = "Deploy Private DNS Resolver"
  type        = bool
  default     = true
}

variable "firewall_sku_tier" {
  description = "Azure Firewall SKU tier"
  type        = string
  default     = "Standard"
}

variable "firewall_availability_zones" {
  description = "Availability zones for firewall"
  type        = list(number)
  default     = []
}

variable "bastion_sku" {
  description = "Azure Bastion SKU"
  type        = string
  default     = "Standard"
}

variable "log_retention_days" {
  description = "Log Analytics workspace retention days"
  type        = number
  default     = 30
}

variable "log_analytics_sku" {
  description = "Log Analytics workspace SKU"
  type        = string
  default     = "PerGB2018"
}

variable "private_dns_zones" {
  description = "List of private DNS zones to create"
  type        = list(string)
  default = [
    "privatelink.eastus2.azmk8s.io",
    "privatelink.azurecr.io",
    "privatelink.vaultcore.azure.net",
    "privatelink.blob.core.windows.net",
    "privatelink.file.core.windows.net",
    "privatelink.queue.core.windows.net",
    "privatelink.table.core.windows.net",
    "privatelink.monitor.azure.com",
    "privatelink.oms.opinsights.azure.com",
  ]
}

variable "onprem_dns_servers" {
  description = "On-premises DNS servers for conditional forwarding"
  type        = list(string)
  default     = []
}

variable "spoke_vnets" {
  description = "Spoke VNets for peering configuration"
  type = map(object({
    name                = string
    resource_group_name = string
    address_space       = list(string)
  }))
  default = {}
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
    Purpose     = "AKS Landing Zone Hub"
  }
}
