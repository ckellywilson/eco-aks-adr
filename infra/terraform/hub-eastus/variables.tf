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
  description = <<-EOT
    Spoke VNets for peering configuration.
    
    Leave empty ({}) for initial hub deployment. After deploying spoke 
    infrastructure, populate this with spoke VNet details and reapply to 
    establish peering connections.
    
    Example:
    spoke_vnets = {
      "spoke-aks-prod" = {
        name                = "vnet-spoke-aks-eus2-prod"
        resource_group_name = "rg-spoke-aks-eus2-prod"
        address_space       = ["10.1.0.0/16"]
      }
    }
  EOT
  type = map(object({
    name                = string
    resource_group_name = string
    address_space       = list(string)
  }))
  default = {}
}

variable "spoke_vnet_address_spaces" {
  description = <<-EOT
    List of spoke VNet address spaces for firewall rules (e.g., ['10.1.0.0/16', '10.2.0.0/16']).
    
    This is used to restrict firewall source addresses to known networks. Should match 
    the address_space values from spoke_vnets. Leave empty ([]) for initial deployment.
  EOT
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
    ManagedBy = "Terraform"
    Purpose   = "AKS Landing Zone Hub"
  }
}
