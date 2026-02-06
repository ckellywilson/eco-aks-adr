# Terraform OIDC & Remote State Configuration Summary

## Changes Made

### 1. **Provider Configuration - OIDC Support** ✅

Both hub and spoke providers now use OIDC:

**Files Updated:**
- [infra/terraform/hub-eastus/providers.tf](../../infra/terraform/hub-eastus/providers.tf)
- [infra/terraform/spoke-aks-prod/providers.tf](../../infra/terraform/spoke-aks-prod/providers.tf)

**Change:**
```hcl
provider "azurerm" {
  subscription_id = var.subscription_id
  use_oidc = true  # ← Added for OIDC support
  
  features {
    # ... existing config
  }
}
```

### 2. **Spoke Data Source - Remote State Reference** ✅

Spoke now reads hub outputs directly from remote state:

**File Updated:**
- [infra/terraform/spoke-aks-prod/data-sources.tf](../../infra/terraform/spoke-aks-prod/data-sources.tf)

**Change:**
```hcl
# Before: JSON file-based approach (fragile)
locals {
  hub_outputs = try(jsondecode(file("../hub-eastus/hub-eastus-outputs.json")), {})
}

# After: Remote state data source (reliable)
data "terraform_remote_state" "hub" {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-terraform-state-dev"
    storage_account_name = "sttfstatedevd3120d7a"
    container_name       = "terraform-state-dev"
    key                  = "hub-eastus/terraform.tfstate"
    use_oidc             = true
  }
}

locals {
  hub_outputs = data.terraform_remote_state.hub.outputs
}
```

**Benefits:**
- No manual file creation needed
- Always reads latest hub state
- Works seamlessly in ADO pipelines
- Automatic dependency management

### 3. **Backend Configuration - OIDC**

**Hub Backend:**
```hcl
backend "azurerm" {
  use_oidc = true
}
```

**Spoke Backend:**
```hcl
backend "azurerm" {
  use_oidc = true
}
```

**ADO Pipeline Usage:**
```bash
terraform init \
  -backend-config="resource_group_name=rg-terraform-state-dev" \
  -backend-config="storage_account_name=sttfstatedevd3120d7a" \
  -backend-config="container_name=terraform-state-dev" \
  -backend-config="key=<path>/terraform.tfstate" \
  -backend-config="use_oidc=true"
```

### 4. **ADO Pipeline Configuration** ✅

Created comprehensive pipeline for deployment:

**File Created:**
- [azure-pipelines.yml](../../azure-pipelines.yml)

**Pipeline Stages:**
1. **Validate** - Syntax checking
2. **PlanHub** - Hub infrastructure plan
3. **ApplyHub** - Hub infrastructure deployment
4. **PlanSpoke** - Spoke infrastructure plan (depends on hub)
5. **ApplySpoke** - Spoke infrastructure deployment

**Key Features:**
- Sequential stages (spoke depends on hub)
- Approval gates for apply stages
- Artifact sharing between stages
- OIDC authentication throughout
- Plan artifacts for review

### 5. **Documentation** ✅

Created setup guide:

**File Created:**
- [docs/ADO-TERRAFORM-SETUP.md](../../docs/ADO-TERRAFORM-SETUP.md)

**Covers:**
- Workload Identity setup
- OIDC federation configuration
- Service connection creation
- Pipeline variables setup
- Troubleshooting guide

## How It Works

### Local Development (with OIDC)
```bash
export ARM_USE_OIDC=true
export ARM_TENANT_ID=38c7b18a-f92a-4353-a784-df16e895da23
export ARM_CLIENT_ID=$(az ad sp list --display-name sp-terraform-ado-oidc --query "[0].appId" -o tsv)
export ARM_SUBSCRIPTION_ID=f8a5f387-2f0b-42f5-b71f-5ee02b8967cf

cd infra/terraform/hub-eastus
terraform init -backend-config=...
terraform plan -var-file=prod.tfvars
```

### ADO Pipeline
1. Pipeline validates both hub and spoke
2. Plans hub infrastructure
3. Applies hub with approval
4. Spoke automatically reads hub state via `terraform_remote_state`
5. Plans spoke infrastructure
6. Applies spoke with approval

## State Architecture

```
Storage Account: sttfstatedevd3120d7a
├── Container: terraform-state-dev
│   ├── hub-eastus/terraform.tfstate
│   │   └── Outputs (firewall_private_ip, dns_resolver_ip, etc.)
│   │
│   └── spoke-aks-prod/terraform.tfstate
│       └── References hub outputs via terraform_remote_state
```

## Authentication Flow

```
Azure CLI OIDC Token
        ↓
Terraform (ARM_USE_OIDC=true)
        ↓
azurerm Provider → Storage Account (remote state)
        ↓
terraform_remote_state (hub outputs)
```

## ADO Pipeline Variables Required

Set these in ADO Pipeline Variables:

| Variable | Value | Secret |
|----------|-------|--------|
| AZURE_SUBSCRIPTION_ID | f8a5f387-2f0b-42f5-b71f-5ee02b8967cf | No |
| AZURE_TENANT_ID | 38c7b18a-f92a-4353-a784-df16e895da23 | No |
| AZURE_CLIENT_ID | \<from service principal\> | Yes |

## Service Connection Setup

Create service connection in ADO:
- **Name**: azure-terraform-connection
- **Type**: Azure Resource Manager
- **Auth**: Service Principal (OIDC)
- **Service Principal**: sp-terraform-ado-oidc
- **Tenant**: 38c7b18a-f92a-4353-a784-df16e895da23

## Validation Checklist

- [x] Providers configured for OIDC
- [x] Hub backend configured for OIDC
- [x] Spoke backend configured for OIDC
- [x] Spoke uses remote state data source
- [x] Removed JSON file dependency
- [x] ADO pipeline created with 5 stages
- [x] Pipeline supports parallel validation
- [x] Hub-to-spoke dependency enforced
- [x] Approval gates for apply stages
- [x] Documentation for setup

## Next Steps

1. Set up Workload Identity federation (see ADO-TERRAFORM-SETUP.md)
2. Create service connection in ADO
3. Set pipeline variables in ADO
4. Run pipeline to validate
5. Approve apply stages to deploy infrastructure

