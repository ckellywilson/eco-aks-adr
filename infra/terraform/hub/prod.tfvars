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

# SSH public key for VM access — set via pipeline secret variable ADMIN_SSH_PUBLIC_KEY
# Local usage: terraform plan -var="admin_ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)"
# Pipeline:    terraform plan -var="admin_ssh_public_key=$(ADMIN_SSH_PUBLIC_KEY)"

# Spoke VNets for peering
# NOTE: Deploying hub first without spoke peering. Will add peering after spoke is deployed.
spoke_vnets = {}

# Spoke VNet address spaces for firewall rules
# Must include all spoke VNet CIDRs to allow outbound traffic through the firewall
spoke_vnet_address_spaces = ["10.1.0.0/16"]

# Resource tags
tags = {
  Purpose     = "AKS Landing Zone Hub"
  ManagedBy   = "Terraform"
  Environment = "prod"
}
