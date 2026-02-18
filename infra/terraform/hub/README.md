# Hub Infrastructure - Azure AKS Landing Zone

This directory contains Terraform code for the hub infrastructure of the Azure AKS landing zone.

## Components

- **VNet**: Hub virtual network with segregated subnets (10.0.0.0/16)
  - AzureFirewallSubnet: 10.0.1.0/26
  - AzureBastionSubnet: 10.0.2.0/27
  - GatewaySubnet: 10.0.3.0/27 (reserved for future VPN/ExpressRoute gateway)
  - Management: 10.0.4.0/24 (jump box VM)
  - DNS Resolver Inbound: 10.0.6.0/28
  - DNS Resolver Outbound: 10.0.7.0/28

- **Azure Firewall**: Centralized egress control for all spokes with AKS-specific rules
- **Azure Bastion**: Secure jumpbox access to management subnet
- **Private DNS Resolver**: Hybrid DNS resolution with forwarding rules
- **Log Analytics Workspace**: Centralized monitoring (30-day retention)
- **Private DNS Zones**: For private endpoints (ACR, Key Vault, AKS API, Storage, etc.)
- **Jump Box VM**: Management VM with Azure CLI, kubectl, Helm, and k9s pre-installed

## Prerequisites

- Terraform 1.14.5 (pinned for production)
- Azure CLI >= 2.50
- Appropriate Azure subscription permissions (Contributor role)
- Storage account for remote state backend already configured
- SSH public key for jump box VM authentication

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

These outputs are exported to `hub-outputs.json` after `terraform apply` and consumed by spoke configurations.

## Configuration Files

- **dev.tfvars**: Development environment variables (must be created based on your environment)
- **prod.tfvars**: Production environment variables (must be created based on your environment)
- **backend-dev.tfbackend**: Dev state backend configuration
- **backend-prod.tfbackend**: Prod state backend configuration

**Note**: The hub `dev.tfvars` and `prod.tfvars` files need to be created with your specific configuration values before deployment. Refer to `variables.tf` for required variables.

## State Management

Terraform state is stored in Azure Storage with separate storage accounts per security boundary:

| Storage Account | Resource Group | Container | Pipeline Pool | Access |
|---|---|---|---|---|
| `sttfstatecicdeus2<suffix>` | `rg-cicd-eus2-prod` | `tfstate-cicd` | MS-hosted (bootstrap), self-hosted (Day 2+) | Public at bootstrap, private after lockdown |
| `sttfstateeus2<suffix>` | `rg-tfstate-eus2-prod` | `tfstate-hub`, `tfstate-spoke` | Self-hosted | Public at bootstrap, private after lockdown (PE from CI/CD VNet) |

### Setting State Container

When initializing, the appropriate backend config selects the correct SA and container:

```bash
# Hub state — Hub+Spoke SA, self-hosted agents
cd infra/terraform/hub
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
- Set `deploy_bastion = false` if you have alternative secure access methods
- Use Premium Firewall tier only if you need TLS inspection or advanced threat protection

## VNet Peering Configuration

The hub infrastructure includes optional VNet peering configuration for connecting spoke networks. By default, `spoke_vnets` is an empty map, allowing the hub to be deployed independently without any spokes.

### Initial Deployment (No Spokes)

On first deployment, leave `spoke_vnets` empty in your tfvars file:

```hcl
# dev.tfvars or prod.tfvars
spoke_vnets = {}
```

This will deploy the hub without any peering connections, which is the recommended approach for initial setup.

### Adding Spoke Peering (After Spoke Deployment)

After deploying spoke infrastructure, update your tfvars file to configure peering:

```hcl
# dev.tfvars or prod.tfvars
spoke_vnets = {
  "spoke-aks-prod" = {
    name                = "vnet-spoke-aks-eus2-prod"
    resource_group_name = "rg-spoke-aks-eus2-prod"
    address_space       = ["10.1.0.0/16"]
  }
  "spoke-data" = {
    name                = "vnet-spoke-data-eus2-prod"
    resource_group_name = "rg-spoke-data-eus2-prod"
    address_space       = ["10.2.0.0/16"]
  }
}

spoke_vnet_address_spaces = ["10.1.0.0/16", "10.2.0.0/16"]
```

Then run `terraform plan` and `terraform apply` to create the peering connections.

### Important Notes

- VNet peering is bidirectional and will be created in both hub and spoke resource groups
- Spoke VNets must exist before configuring peering (data source will fail otherwise)
- The `spoke_vnet_address_spaces` variable is used for firewall source address restrictions
- Peering allows forwarded traffic to enable hub firewall routing

## Next Steps

1. Deploy hub infrastructure (without spokes)
2. Generate outputs: `hub-outputs.json`
3. Review outputs
4. Deploy spoke infrastructure referencing hub outputs
5. Update hub configuration with spoke_vnets and redeploy to establish peering
6. Configure firewall rules as needed for spoke traffic

## Documentation

- [Azure AKS Landing Zone Design](../../README.md)
- [Terraform Registry - Azure Verified Modules](https://registry.terraform.io/search/modules?namespace=Azure)
- [Hub-Spoke Architecture Pattern](https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/hybrid-networking/hub-spoke)
