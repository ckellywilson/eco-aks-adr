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
  description = "Azure DevOps agent pool name for self-hosted Container App Job agents"
  type        = string
  default     = "aci-cicd-pool"
}

# --- Container App Job Settings ---

variable "container_app_max_execution_count" {
  description = "Maximum number of concurrent Container App Job executions (KEDA scaling upper bound)"
  type        = number
  default     = 10
}

variable "container_app_min_execution_count" {
  description = "Minimum number of Container App Job executions (0 = scale to zero when idle)"
  type        = number
  default     = 0
}

variable "container_app_polling_interval" {
  description = "KEDA polling interval in seconds (how often to check ADO queue for pending jobs)"
  type        = number
  default     = 30
}

variable "container_app_cpu" {
  description = "CPU cores per Container App Job execution (e.g. 2)"
  type        = number
  default     = 2
}

variable "container_app_memory" {
  description = "Memory in GB per Container App Job execution (e.g. 4)"
  type        = string
  default     = "4Gi"
}

# --- Networking ---

variable "container_app_subnet_cidr" {
  description = "CIDR for Container App Environment subnet (min /27, delegation: Microsoft.App/environments)"
  type        = string
  default     = "10.2.0.0/27"
}

variable "aci_agents_acr_subnet_cidr" {
  description = "CIDR for ACR private endpoint subnet"
  type        = string
  default     = "10.2.0.32/29"
}

variable "private_endpoints_subnet_cidr" {
  description = "CIDR for state SA and platform KV private endpoints"
  type        = string
  default     = "10.2.0.48/28"
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

# --- Terraform State Storage Account ---

variable "state_storage_account_id" {
  description = "Resource ID of the Terraform state storage account for private endpoint"
  type        = string
  default     = ""
}

# --- Hub Integration (Optional — empty defaults for bootstrap) ---

variable "hub_vnet_id" {
  description = "Hub VNet resource ID for peering. Empty string disables peering."
  type        = string
  default     = ""
}

variable "hub_dns_resolver_ip" {
  description = "Hub DNS resolver inbound IP for VNet custom DNS. Empty string uses Azure default DNS."
  type        = string
  default     = ""
}

variable "hub_acr_dns_zone_id" {
  description = "Hub privatelink.azurecr.io DNS zone ID for ACR PE. Empty string creates CI/CD-owned zone."
  type        = string
  default     = ""
}

variable "hub_log_analytics_workspace_id" {
  description = "Hub Log Analytics workspace resource ID. Empty string disables centralized logging."
  type        = string
  default     = ""
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
