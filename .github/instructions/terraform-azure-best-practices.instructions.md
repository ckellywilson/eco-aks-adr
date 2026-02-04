---
description: 'Terraform Azure Best Practices and AVM Consumption'
applyTo: '**/*.terraform, **/*.tf, **/*.tfvars, **/*.tfstate, **/*.tflint.hcl, **/*.tf.json, **/*.tfvars.json'
---

# Terraform Azure Best Practices

## Overview

This repository generates Azure infrastructure as code following Microsoft best practices and consuming Azure Verified Modules (AVM) where available. We focus on producing high-quality, maintainable infrastructure code rather than contributing to AVM itself.

## Custom Instructions for GitHub Copilot Agents

**IMPORTANT**: This repository uses a **three-tiered validation approach** to balance developer productivity with code quality:

### Tier 1: Pre-Commit (Fast - Every Commit)

Fast checks that run in 5-10 seconds:

```bash
terraform fmt -recursive
terraform validate
```

**When:** Before every `git commit`  
**Time:** 5-10 seconds  
**Purpose:** Catch formatting and syntax errors immediately

### Tier 2: Pre-PR (Moderate - Before Pull Request)

Comprehensive validation that runs in 1-3 minutes:

```bash
terraform fmt -check -recursive
terraform validate
tfsec . --minimum-severity MEDIUM
```

**When:** Before creating pull request  
**Time:** 1-3 minutes  
**Purpose:** Auto-fix code issues, run security checks

### Tier 3: CI/CD (Full - Automated)

Full validation in 5-15 minutes - runs automatically in GitHub Actions/Azure DevOps pipelines with terraform plan, policy scans, and well-architected checks.

**Note:** Tier 3 is automated after you set up CI/CD workflows. Until then, Tier 2 validation is sufficient for PR approval.

## Module Discovery and Usage

### Finding Azure Verified Modules

#### Terraform Registry

- **Search**: [Terraform Registry - Azure Modules](https://registry.terraform.io/search/modules?namespace=Azure)
- **Search pattern**: "avm" + resource name, filter by "Partner" tag
- **Example**: Search "avm storage account" → filter by Partner

#### Official AVM Index

The following links point to the latest version of the CSV files on the main branch:

- **Terraform Resource Modules**: `https://raw.githubusercontent.com/Azure/Azure-Verified-Modules/refs/heads/main/docs/static/module-indexes/TerraformResourceModules.csv`
- **Terraform Pattern Modules**: `https://raw.githubusercontent.com/Azure/Azure-Verified-Modules/refs/heads/main/docs/static/module-indexes/TerraformPatternModules.csv`
- **Terraform Utility Modules**: `https://raw.githubusercontent.com/Azure/Azure-Verified-Modules/refs/heads/main/docs/static/module-indexes/TerraformUtilityModules.csv`

### Consuming Azure Verified Modules

#### From Examples

1. Copy the example code from the module documentation
2. Replace `source = "../../"` with `source = "Azure/avm-res-{service}-{resource}/azurerm"`
3. Add `version = "~> 1.0"` (use latest available)
4. Set `enable_telemetry = true`

#### From Scratch

1. Copy the Provision Instructions from module documentation
2. Configure required and optional inputs
3. Pin the module version
4. Enable telemetry

#### Example Usage

```hcl
module "storage_account" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "~> 0.1"

  enable_telemetry    = true
  location            = "East US"
  name                = "mystorageaccount"
  resource_group_name = "my-rg"

  # Additional configuration...
}
```

## Naming Conventions

### Module Types

- **Resource Modules**: `Azure/avm-res-{service}-{resource}/azurerm`
  - Example: `Azure/avm-res-storage-storageaccount/azurerm`
- **Pattern Modules**: `Azure/avm-ptn-{pattern}/azurerm`
  - Example: `Azure/avm-ptn-aks-enterprise/azurerm`
- **Utility Modules**: `Azure/avm-utl-{utility}/azurerm`
  - Example: `Azure/avm-utl-regions/azurerm`

### Service Naming

- Use kebab-case for services and resources
- Follow Azure service names (e.g., `storage-storageaccount`, `network-virtualnetwork`)

## Version Management

### Check Available Versions

- Endpoint: `https://registry.terraform.io/v1/modules/Azure/{module}/azurerm/versions`
- Example: `https://registry.terraform.io/v1/modules/Azure/avm-res-storage-storageaccount/azurerm/versions`

### Version Pinning Best Practices

- Use pessimistic version constraints: `version = "~> 1.0"`
- Pin to specific versions for production: `version = "1.2.3"`
- Always review changelog before upgrading

## Module Sources

### Terraform Registry

- **URL Pattern**: `https://registry.terraform.io/modules/Azure/{module}/azurerm/latest`
- **Example**: `https://registry.terraform.io/modules/Azure/avm-res-storage-storageaccount/azurerm/latest`

### GitHub Repository

- **URL Pattern**: `https://github.com/Azure/terraform-azurerm-avm-{type}-{service}-{resource}`
- **Examples**:
  - Resource: `https://github.com/Azure/terraform-azurerm-avm-res-storage-storageaccount`
  - Pattern: `https://github.com/Azure/terraform-azurerm-avm-ptn-aks-enterprise`

## Development Best Practices

### Module Usage

- ✅ **Always** pin module and provider versions
- ✅ **Start** with official examples from module documentation
- ✅ **Review** all inputs and outputs before implementation
- ✅ **Enable** telemetry: `enable_telemetry = true`
- ✅ **Use** AVM utility modules for common patterns
- ✅ **Follow** AzureRM provider requirements and constraints

### Code Quality

- ✅ **Always** run `terraform fmt` after making changes
- ✅ **Always** run `terraform validate` after making changes
- ✅ **Use** meaningful variable names and descriptions
- ✅ **Add** proper tags and metadata
- ✅ **Document** complex configurations

### Pre-Submission Checklist

Before creating or updating any pull request:

```bash
# Format code
terraform fmt -recursive

# Validate syntax
terraform validate

# Security checks
tfsec . --minimum-severity MEDIUM
```

## Tool Integration

### Use Available Tools

- **Deployment Guidance**: Use deployment best practices documentation
- **Service Documentation**: Use Microsoft Learn for Azure service-specific guidance
- **Schema Information**: Refer to Terraform AzureRM provider documentation for resource details

### GitHub Copilot Integration

When working with infrastructure code:

1. Always check for existing AVM modules before creating custom resources
2. Use official examples as starting points
3. Run all validation tests before committing
4. Document any customizations or deviations from examples

## Common Patterns

### Resource Group Module

```hcl
module "resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "~> 0.1"

  enable_telemetry = true
  location         = var.location
  name            = var.resource_group_name
}
```

### Virtual Network Module

```hcl
module "virtual_network" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "~> 0.1"

  enable_telemetry    = true
  location            = module.resource_group.location
  name                = var.vnet_name
  resource_group_name = module.resource_group.name
  address_space       = ["10.0.0.0/16"]
}
```

## Troubleshooting

### Common Issues

1. **Version Conflicts**: Always check compatibility between module and provider versions
2. **Missing Dependencies**: Ensure all required resources are created first
3. **Validation Failures**: Run validation tools before committing
4. **Documentation**: Always refer to the latest module documentation

### Support Resources

- **AVM Documentation**: `https://azure.github.io/Azure-Verified-Modules/`
- **GitHub Issues**: Report issues in the specific module's GitHub repository
- **Community**: Azure Terraform Provider GitHub discussions

## Compliance Checklist

Before submitting any infrastructure code:

- [ ] Module versions are pinned
- [ ] Telemetry is enabled (if AVM module used)
- [ ] Code is formatted (`terraform fmt`)
- [ ] Code is validated (`terraform validate`)
- [ ] Security checks pass (`tfsec . --minimum-severity MEDIUM`)
- [ ] Documentation is updated
- [ ] Examples are tested and working
