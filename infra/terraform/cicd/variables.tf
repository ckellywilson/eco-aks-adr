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
  description = "Resource ID of the platform Key Vault containing SSH keys and platform secrets. Empty at bootstrap if KV doesn't exist yet."
  type        = string
  default     = ""

  validation {
    condition     = var.platform_key_vault_id == "" || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.KeyVault/vaults/[^/]+$", var.platform_key_vault_id))
    error_message = "platform_key_vault_id must be empty or a valid Azure Key Vault resource ID."
  }
}

# --- Terraform State Storage Accounts ---

variable "state_storage_account_id" {
  description = "Resource ID of the CI/CD Terraform state storage account for private endpoint"
  type        = string
  default     = ""
}

variable "hub_spoke_state_storage_account_id" {
  description = "Resource ID of the Hub+Spoke state storage account for private endpoint. Provide when this SA exists and you want CI/CD to create a PE (can be set at bootstrap or Day 2)."
  type        = string
  default     = ""
}

# --- Hub Integration (optional — empty for bootstrap, populated Day 2) ---

variable "hub_vnet_id" {
  description = "Hub VNet resource ID for peering. Empty = no peering (bootstrap mode)."
  type        = string
  default     = ""

  validation {
    condition     = var.hub_vnet_id == "" || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+$", var.hub_vnet_id))
    error_message = "hub_vnet_id must be empty or a valid Azure VNet resource ID."
  }
}

variable "hub_dns_resolver_ip" {
  description = "Hub DNS resolver inbound IP for VNet custom DNS. Empty = Azure default DNS (bootstrap mode)."
  type        = string
  default     = ""

  validation {
    condition     = var.hub_dns_resolver_ip == "" || (can(regex("^\\d+\\.\\d+\\.\\d+\\.\\d+$", var.hub_dns_resolver_ip)) && var.hub_vnet_id != "")
    error_message = "hub_dns_resolver_ip must be empty or a valid IPv4 address, and when set hub_vnet_id must also be provided."
  }
}

variable "hub_acr_dns_zone_id" {
  description = "Hub privatelink.azurecr.io DNS zone ID. Empty = CI/CD creates its own zone (bootstrap mode). Requires hub_dns_resolver_ip when set."
  type        = string
  default     = ""

  validation {
    condition     = var.hub_acr_dns_zone_id == "" || var.hub_dns_resolver_ip != ""
    error_message = "hub_acr_dns_zone_id requires hub_dns_resolver_ip (and hub_vnet_id) to be set — hub zones are only resolvable via the hub DNS resolver."
  }
}

variable "hub_blob_dns_zone_id" {
  description = "Hub privatelink.blob.core.windows.net DNS zone ID. Empty = CI/CD creates its own zone (bootstrap mode). Requires hub_dns_resolver_ip when set."
  type        = string
  default     = ""

  validation {
    condition     = var.hub_blob_dns_zone_id == "" || var.hub_dns_resolver_ip != ""
    error_message = "hub_blob_dns_zone_id requires hub_dns_resolver_ip (and hub_vnet_id) to be set — hub zones are only resolvable via the hub DNS resolver."
  }
}

variable "hub_vault_dns_zone_id" {
  description = "Hub privatelink.vaultcore.azure.net DNS zone ID. Empty = CI/CD creates its own zone (bootstrap mode). Requires hub_dns_resolver_ip when set."
  type        = string
  default     = ""

  validation {
    condition     = var.hub_vault_dns_zone_id == "" || var.hub_dns_resolver_ip != ""
    error_message = "hub_vault_dns_zone_id requires hub_dns_resolver_ip (and hub_vnet_id) to be set — hub zones are only resolvable via the hub DNS resolver."
  }
}

variable "hub_log_analytics_workspace_id" {
  description = "Hub Log Analytics workspace resource ID. Empty = module creates its own (bootstrap mode)."
  type        = string
  default     = ""
}

# --- Spoke VNet Peering (for kubectl/Helm access to private AKS clusters) ---

variable "spoke_vnet_ids" {
  description = "Map of spoke name to VNet resource ID for bidirectional peering. Enables CI/CD agents to reach private AKS API servers. VNet peering is not transitive, so each spoke needs a direct peering."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for v in values(var.spoke_vnet_ids) : can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+$", v))])
    error_message = "Each spoke_vnet_ids value must be a valid Azure VNet resource ID."
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
