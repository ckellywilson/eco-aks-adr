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

variable "deploy_jumpbox" {
  description = "Deploy jump box VM for accessing AKS cluster"
  type        = bool
  default     = false
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
    Spoke VNets configuration. Supports two provisioning modes per spoke:
    
    - hub_managed = true:  Hub creates the spoke RG + VNet (centralized control).
                           Spoke deployments deploy INTO the hub-created RG/VNet.
    - hub_managed = false: Spoke RG + VNet already exist (delegated to dev teams).
                           Hub only creates bidirectional peering.
    
    Leave empty ({}) for initial hub-only deployment.
    
    Example:
    spoke_vnets = {
      "spoke-aks-prod" = {
        hub_managed         = true
        name                = "vnet-aks-prod-eus2"
        resource_group_name = "rg-aks-eus2-prod"
        address_space       = ["10.1.0.0/16"]
      }
    }
  EOT
  type = map(object({
    hub_managed         = bool
    name                = string
    resource_group_name = string
    address_space       = list(string)
  }))
  default = {}
}

variable "spoke_vnet_address_spaces" {
  description = <<-EOT
    Additional spoke VNet address spaces for firewall rules not in spoke_vnets.
    Address spaces from spoke_vnets are automatically included.
    Typically left empty — only needed for VNets not managed via spoke_vnets.
  EOT
  type        = list(string)
  default     = []
}

variable "admin_username" {
  description = "Admin username for jump box VMs"
  type        = string
  default     = "azureuser"
}

variable "platform_key_vault_id" {
  description = "Resource ID of the platform Key Vault containing SSH keys and platform secrets (created by setup-ado-pipeline.sh)"
  type        = string
}

variable "deploy_cicd_agents" {
  description = "Deploy self-hosted ACI-based ADO pipeline agents in the hub VNet"
  type        = bool
  default     = false
}

variable "ado_organization_url" {
  description = "Azure DevOps organization URL (e.g. https://dev.azure.com/myorg)"
  type        = string
  default     = ""
}

variable "ado_agent_pool_name" {
  description = "Azure DevOps agent pool name for self-hosted ACI agents"
  type        = string
  default     = "aci-hub-pool"
}

variable "aci_agent_count" {
  description = "Number of ACI-based ADO agent instances"
  type        = number
  default     = 2
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    ManagedBy = "Terraform"
    Purpose   = "AKS Landing Zone Hub"
  }
}
