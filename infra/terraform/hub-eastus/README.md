# Hub Infrastructure - Azure AKS Landing Zone

This directory contains Terraform code for the hub infrastructure of the Azure AKS landing zone.

## Components

- **VNet**: Hub virtual network with segregated subnets (10.0.0.0/16)
  - AzureFirewallSubnet: 10.0.1.0/26
  - AzureBastionSubnet: 10.0.2.0/27
  - GatewaySubnet: 10.0.3.0/27
  - Management: 10.0.4.0/24
  - AppGatewaySubnet: 10.0.5.0/26

- **Azure Firewall**: Centralized egress control for all spokes
- **Azure Bastion**: Secure jumpbox access
- **Log Analytics Workspace**: Centralized monitoring (30-day retention)
- **Private DNS Zones**: For private endpoints (ACR, Key Vault, AKS API, Storage, etc.)

## Prerequisites

- Terraform >= 1.9
- Azure CLI >= 2.50
- Appropriate Azure subscription permissions (Contributor role)
- Storage account for remote state backend already configured

## Deployment

### Step 1: Initialize Terraform

```bash
# Dev environment
terraform init -backend-config="backend-dev.tfbackend"

# Prod environment
terraform init -backend-config="backend-prod.tfbackend"
```

### Step 2: Review Plan

```bash
# Dev environment
terraform plan -var-file="dev.tfvars" -out=tfplan

# Prod environment
terraform plan -var-file="prod.tfvars" -out=tfplan
```

### Step 3: Apply Changes

```bash
terraform apply tfplan
```

### Using the Deploy Script

Alternatively, use the provided deploy script:

```bash
# Deploy to dev
./deploy.sh dev

# Deploy to prod
./deploy.sh prod
```

## Outputs

After deployment, the following outputs are available:

- `hub_vnet_id`: Hub VNet resource ID (used by spokes for peering)
- `hub_subnets`: Map of subnet IDs (used for spoke routing)
- `firewall_private_ip`: Firewall IP for UDR configuration
- `log_analytics_workspace_id`: Workspace ID for spoke diagnostic settings
- `private_dns_zone_ids`: Map of DNS zone IDs for spoke private endpoints

These outputs are exported to `hub-eastus-outputs.json` after `terraform apply` and consumed by spoke configurations.

## Configuration Files

- **dev.tfvars**: Development environment variables
- **prod.tfvars**: Production environment variables
- **backend-dev.tfbackend**: Dev state backend configuration
- **backend-prod.tfbackend**: Prod state backend configuration

## State Management

Terraform state is stored in Azure Storage:
- Storage Account: sttfstatedevd3120d7a
- Resource Group: rg-terraform-state-dev
- Containers: terraform-state-dev, terraform-state-prod

### Setting State Container

When initializing, the appropriate container is selected based on the backend config:

```bash
# Creates/uses terraform-state-dev container
terraform init -backend-config="backend-dev.tfbackend"

# Creates/uses terraform-state-prod container
terraform init -backend-config="backend-prod.tfbackend"
```

## Validation

Before deploying, validate the code:

```bash
# Format check
terraform fmt -check

# Syntax validation
terraform init -backend=false
terraform validate

# Security scan (if tfsec available)
tfsec . --minimum-severity MEDIUM
```

## Troubleshooting

### Module Not Found

If you get "module not found" errors during `terraform init`, ensure:

1. You have internet access (modules are downloaded from Terraform Registry)
2. Azure CLI is authenticated: `az login`
3. Terraform provider is properly configured

### State Lock Issues

If state is locked:

```bash
# View lock ID
terraform state list

# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

### Firewall Policy Issues

Azure Firewall requires a policy. The code creates a basic policy. To add rules:

```hcl
# Add to firewall policy configuration
resource "azurerm_firewall_policy_rule_collection_group" "example" {
  name               = "example-rcg"
  priority           = 100
  firewall_policy_id = azurerm_firewall_policy.hub[0].id

  # Add rule collections here
}
```

## Cost Optimization

Default configuration deploys:
- 1 Azure Firewall (Standard tier) - ~$1.25/hour
- 1 Azure Bastion (Standard tier) - ~$0.16/hour
- 1 Log Analytics workspace (PerGB2018) - ~$0.99/GB ingested
- Private DNS Zones - ~$0.50 per zone/month

**Total monthly cost**: ~$800-1200 (varies with traffic)

To reduce costs:
- Set `deploy_firewall = false` to remove firewall (~$900/month savings)
- Set `deploy_application_gateway = false` if not using App Gateway
- Use Premium Firewall tier only if you need HTTP/S inspection

## Next Steps

1. Deploy hub infrastructure
2. Generate outputs: `hub-eastus-outputs.json`
3. Review outputs
4. Deploy spoke infrastructure referencing hub outputs
5. Configure firewall rules as needed for spoke traffic

## Documentation

- [Azure AKS Landing Zone Design](../../README.md)
- [Terraform Registry - Azure Verified Modules](https://registry.terraform.io/search/modules?namespace=Azure)
- [Hub-Spoke Architecture Pattern](https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/hybrid-networking/hub-spoke)
