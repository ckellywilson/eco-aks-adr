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

# --- CI/CD Resource Group & VNet ---

variable "cicd_resource_group_name" {
  description = "Name of the CI/CD resource group (self-contained, not hub-managed)"
  type        = string
  default     = "rg-cicd-eus2-prod"
}

variable "cicd_vnet_name" {
  description = "Name of the CI/CD VNet"
  type        = string
  default     = "vnet-cicd-prod-eus2"
}

variable "cicd_vnet_address_space" {
  description = "Address space for the CI/CD VNet"
  type        = list(string)
  default     = ["10.2.0.0/24"]
}

# --- ADO Configuration ---

variable "ado_organization_url" {
  description = "Azure DevOps organization URL (e.g. https://dev.azure.com/myorg)"
  type        = string

  validation {
    condition     = can(regex("^https://dev\\.azure\\.com/.+$", var.ado_organization_url))
    error_message = "ado_organization_url must be a valid Azure DevOps URL (https://dev.azure.com/<org>)."
  }
}

variable "ado_agent_pool_name" {
  description = "Azure DevOps agent pool name for self-hosted ACI agents"
  type        = string
  default     = "aci-cicd-pool"
}

variable "aci_agent_count" {
  description = "Number of ACI-based ADO agent instances"
  type        = number
  default     = 2

  validation {
    condition     = var.aci_agent_count > 0
    error_message = "aci_agent_count must be greater than 0."
  }
}

# --- Networking ---

variable "aci_agents_subnet_cidr" {
  description = "CIDR for ACI agents subnet"
  type        = string
  default     = "10.2.0.0/27"
}

variable "aci_agents_acr_subnet_cidr" {
  description = "CIDR for ACR private endpoint subnet"
  type        = string
  default     = "10.2.0.32/29"
}

# --- Platform Key Vault ---

variable "platform_key_vault_id" {
  description = "Resource ID of the platform Key Vault containing SSH keys and platform secrets"
  type        = string

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.KeyVault/vaults/[^/]+$", var.platform_key_vault_id))
    error_message = "platform_key_vault_id must be a valid Azure Key Vault resource ID."
  }
}

# --- Tags ---

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    ManagedBy = "Terraform"
    Purpose   = "AKS Landing Zone CI/CD"
  }
}
