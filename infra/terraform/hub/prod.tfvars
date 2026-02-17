# Hub Production Environment Variables
subscription_id = "f8a5f387-2f0b-42f5-b71f-5ee02b8967cf"

environment         = "prod"
location            = "eastus2"
location_code       = "eus2"
resource_group_name = "rg-hub-eus2-prod"

# Network configuration
hub_vnet_address_space = ["10.0.0.0/16"]

# Firewall configuration
firewall_sku_tier = "Standard"
deploy_firewall   = true

# Bastion configuration
bastion_sku    = "Standard"
deploy_bastion = true

# DNS Resolver
deploy_dns_resolver = true

# Logging
log_retention_days = 30
log_analytics_sku  = "PerGB2018"

# Firewall availability zones (empty list = no zones, Standard SKU)
firewall_availability_zones = []

# SSH public key for VM access — stored in platform Key Vault
# Created by setup-ado-pipeline.sh; read via data source in Terraform
# Platform KV resource ID (set via pipeline or tfvars)
# platform_key_vault_id = "<set-by-pipeline-or-manually>"

# Spoke VNets — hub creates RG + VNet for hub_managed spokes
spoke_vnets = {
  "spoke-aks-prod" = {
    hub_managed         = true
    name                = "vnet-aks-prod-eus2"
    resource_group_name = "rg-aks-eus2-prod"
    address_space       = ["10.1.0.0/16"]
  }
}

# Additional spoke address spaces not in spoke_vnets (for firewall rules)
spoke_vnet_address_spaces = ["10.2.0.0/24"]

# Resource tags
tags = {
  Purpose     = "AKS Landing Zone Hub"
  ManagedBy   = "Terraform"
  Environment = "prod"
}
