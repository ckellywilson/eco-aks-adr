# CI/CD Landing Zone Production Environment Variables
subscription_id = "f8a5f387-2f0b-42f5-b71f-5ee02b8967cf"

environment = "prod"
location    = "eastus2"

# CI/CD resource group and VNet (self-contained, not hub-managed)
cicd_resource_group_name = "rg-cicd-eus2-prod"
cicd_vnet_name           = "vnet-cicd-prod-eus2"
cicd_vnet_address_space  = ["10.2.0.0/24"]

# ADO configuration
ado_organization_url = "https://dev.azure.com/modenv496195"
ado_agent_pool_name  = "aci-cicd-pool"
aci_agent_count      = 2

# Subnet CIDRs within CI/CD VNet (10.2.0.0/24)
aci_agents_subnet_cidr     = "10.2.0.0/27"
aci_agents_acr_subnet_cidr = "10.2.0.32/29"

# Platform Key Vault (set via pipeline variable or manually)
# platform_key_vault_id = "<set-by-pipeline-or-manually>"

# Resource tags
tags = {
  Purpose     = "AKS Landing Zone CI/CD"
  ManagedBy   = "Terraform"
  Environment = "prod"
}
