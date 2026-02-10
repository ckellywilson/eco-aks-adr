# Azure DevOps Pipelines

This directory contains Azure DevOps pipeline definitions for deploying and managing Azure infrastructure using Terraform.

**⚠️ IMPORTANT**: See [SETUP.md](SETUP.md) for critical setup requirements based on **Microsoft official best practices**.

## Overview

These pipelines implement a complete Terraform workflow following Microsoft's recommended patterns:
- **Service Connection-based authentication** (not raw credentials)
- **Four-stage deployment**: Validate → Init → Plan → Apply
- **Static code analysis** with security scanning
- **Production deployment gates** with environment approvals

## Quick Start

1. **Read [SETUP.md](SETUP.md)** - Contains required Azure DevOps setup
2. **Create Azure Service Principal** (instructions in SETUP.md)
3. **Create Azure Service Connection** (instructions in SETUP.md)
4. **Create Environments** (Hub-Production and Spoke-Production)
5. **Push to repository** to trigger pipelines

## Pipeline Structure

### Main Pipelines

- **`pipelines/hub-deploy.yml`** - Deploys hub network infrastructure
  - Triggers on changes to `infra/terraform/hub-eastus/`
  - Requires `Hub-Production` environment approval for apply

- **`pipelines/spoke-deploy.yml`** - Deploys spoke AKS infrastructure
  - Triggers on changes to `infra/terraform/spoke-aks-prod/`
  - Requires `Spoke-Production` environment approval for apply

### Reusable Templates

Located in `pipelines/templates/`:

- **`terraform-validate.yml`** - Format, syntax, and security checks
- **`terraform-init.yml`** - Backend initialization with proper authentication
- **`terraform-plan.yml`** - Generate execution plans
- **`terraform-apply.yml`** - Apply plans with proper state handling

## Pipeline Stages (Detailed)

### 1️⃣ Validate Stage
Runs on all commits and PRs

```
✓ terraform fmt -check          Check code formatting
✓ terraform init -backend=false Validate syntax
✓ terraform validate            Verify configuration
✓ tfsec                          Security scan
```

### 2️⃣ Init Stage  
Initializes Terraform backend with remote state

```
✓ Get storage account access key from Azure
✓ terraform init                Initialize backend
✓ Configure state locking
```

### 3️⃣ Plan Stage
Generates execution plan for review

```
✓ terraform plan                Generate changes
✓ Publish plan as artifact      For review and apply stage
```

### 4️⃣ Apply Stage
Applies infrastructure changes (main branch only, requires approval)

```
✓ Approval gate (environment)    Production deployment protection
✓ terraform apply               Apply the plan
✓ Publish outputs               Save output values
```

## Key Features

✅ **Service Connection Authentication**
- Uses Azure DevOps Service Connections (recommended by Microsoft)
- Proper credential management and RBAC
- Eliminates authentication errors

✅ **Proper State Backend Configuration**
- Explicit access key retrieval via Azure CLI
- State locking via Azure Storage blob leases
- Supports multi-region deployments

✅ **Complete Validation**
- Code formatting checks
- Syntax validation
- Configuration validation
- Security scanning with tfsec

✅ **Production Safety**
- Environment approvals required for apply
- Plan review before changes
- Separate approval gates per infrastructure

✅ **Artifact Management**
- Plans published for review
- Outputs captured for reference
- Security reports generated

## Configuration

### Required Variables

Edit each pipeline YAML to match your environment:

```yaml
variables:
  terraformVersion: '1.9'                          # Terraform version
  azureServiceConnection: 'Azure-Terraform-Connection'  # Service connection name
  backendResourceGroup: 'rg-terraform-state'       # State storage RG
  backendStorageAccount: 'tfstate'                 # Storage account name
  backendContainer: 'terraform'                    # Container name
```

### Service Connection

Create in Azure DevOps: **Project Settings → Service Connections**

Required name: `Azure-Terraform-Connection`

Must have `Contributor` role on the subscription.

### Environments

Create two environments for approval gates:
- `Hub-Production` - Approves hub infrastructure changes
- `Spoke-Production` - Approves spoke infrastructure changes

Navigate to: **Pipelines → Environments**

## Triggering Pipelines

### Automatic (Recommended)

Pipelines trigger automatically on:

**Hub Pipeline**
- Push to `main` with changes in `infra/terraform/hub-eastus/`
- PR to `main` with changes in `infra/terraform/hub-eastus/`

**Spoke Pipeline**
- Push to `main` with changes in `infra/terraform/spoke-aks-prod/`
- PR to `main` with changes in `infra/terraform/spoke-aks-prod/`

### Manual

Queue pipelines directly in Azure DevOps web UI.

## State Management

### Backend Configuration

State is stored in Azure Storage with locking:

```
Resource Group: rg-terraform-state
Storage Account: tfstate
Container: terraform

State Files:
  hub-eastus.tfstate       (hub infrastructure)
  spoke-aks-prod.tfstate   (spoke infrastructure)
```

### State Locking

Automatic state locking prevents concurrent modifications. If a lock persists after a failed run:

```bash
# Via Azure Portal:
# 1. Open storage account tfstate
# 2. Browse to terraform container
# 3. Click blob name (*
.tfstate.lock)
# 4. Click "..." → "Break Lease"

# Via Azure CLI:
az storage blob lease break \
  --account-name tfstate \
  --container-name terraform \
  --blob-name "hub-eastus.tfstate.lock"
```

## Best Practices

### Development Workflow

1. Create feature branch
2. Make Terraform changes
3. Push to feature branch (triggers validation)
4. Review plan in Azure DevOps
5. Create PR to main
6. Validate passes in PR check
7. Merge to main
8. Apply stage runs with approval gate

### Code Quality

- ✅ Always run `terraform fmt -recursive` locally before pushing
- ✅ Run `terraform validate` to catch errors early
- ✅ Review `terraform plan` output carefully
- ✅ Keep changes focused and well-documented
- ✅ Use meaningful commit messages

### Security

- ✅ Service Connection credentials managed by Azure DevOps
- ✅ State files encrypted in Azure Storage
- ✅ Access controlled via RBAC
- ✅ Sensitive outputs marked in Terraform
- ✅ Security scanning runs automatically
- ❌ Never commit `.tfstate` files
- ❌ Never hardcode secrets in YAML

## Troubleshooting

### Common Issues

**Q: Pipeline fails with "Error acquiring the state lock"**
- See [SETUP.md](SETUP.md) Troubleshooting section
- Use Azure Portal or Azure CLI to break lease

**Q: Service connection fails with authorization error**
- Verify service principal has `Contributor` role
- Check service connection is named correctly
- Re-test connection in Azure DevOps settings

**Q: Plan shows unexpected changes**
- Run `terraform refresh` locally
- Verify variables match (prod.tfvars)
- Check for drift detection

### Debug Mode

Enable detailed Terraform logging:

Edit pipeline template and add:
```bash
export TF_LOG=DEBUG
terraform <command>
```

## Files Structure

```
.azdo/
├── README.md                 This file
├── SETUP.md                  Setup instructions (important!)
└── pipelines/
    ├── hub-deploy.yml        Hub infrastructure pipeline
    ├── spoke-deploy.yml      Spoke AKS pipeline
    └── templates/
        ├── terraform-validate.yml
        ├── terraform-init.yml
        ├── terraform-plan.yml
        └── terraform-apply.yml
```

## References

### Microsoft Official Documentation
- [Azure DevOps Terraform Best Practices](https://learn.microsoft.com/en-us/azure/developer/terraform/best-practices-integration-testing)
- [Troubleshooting Terraform on Azure](https://learn.microsoft.com/en-us/azure/developer/terraform/troubleshoot)
- [Store Terraform State in Azure Storage](https://learn.microsoft.com/en-us/azure/developer/terraform/store-state-in-azure-storage)

### Azure DevOps
- [Service Connections Documentation](https://learn.microsoft.com/en-us/azure/devops/pipelines/library/connect-to-azure)
- [YAML Pipeline Syntax](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema)

### Terraform
- [Terraform CLI Commands](https://developer.hashicorp.com/terraform/cli/commands)
- [Azure Provider Authentication](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs#authenticating-to-azure)

## Support

For issues:

1. **Check SETUP.md** - Most issues are setup-related
2. **Review pipeline logs** in Azure DevOps (full output)
3. **Verify service connection** works locally: `az account show`
4. **Check storage backend** can be accessed from pipeline agent
5. **Review Azure provider** permissions in Azure Portal

## Version History

- **v2.0** (Feb 2026) - Rewritten following Microsoft best practices
  - Service Connection-based authentication
  - Proper state backend configuration
  - Complete validation pipeline
  - Production deployment gates
  
- **v1.0** (Earlier) - Initial pipeline setup
