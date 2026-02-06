# ADO Pipeline Setup for Terraform Deployment with OIDC

## Overview

This project uses Azure DevOps Pipelines to deploy hub and spoke infrastructure via Terraform, with OIDC (OpenID Connect) for authentication to Azure and remote state management.

## Prerequisites

1. **Azure DevOps Organization** and a project in your organization
2. **Azure Workload Identity** configured for OIDC federation
3. **Service Principal** with Workload Identity federation enabled
4. **Storage Account** for remote Terraform state

## Architecture

```
ADO Pipeline
    ↓
  OIDC Token
    ↓
Workload Identity (Service Principal)
    ↓
Azure Resources + Remote State Storage
```

## Setup Steps

### 1. Create Workload Identity (Service Principal) with OIDC Federation

```bash
# Set variables
TENANT_ID="38c7b18a-f92a-4353-a784-df16e895da23"
SUBSCRIPTION_ID="f8a5f387-2f0b-42f5-b71f-5ee02b8967cf"
SERVICE_PRINCIPAL_NAME="sp-terraform-ado-oidc"
ADO_ORG="YourOrgName"
ADO_PROJECT="YourProjectName"

# Create service principal
az ad sp create-for-rbac \
  --name $SERVICE_PRINCIPAL_NAME \
  --role Contributor \
  --scopes /subscriptions/$SUBSCRIPTION_ID

# Note the returned clientId and objectId

# Add OIDC federated credentials
CLIENT_ID=$(az ad sp list --display-name $SERVICE_PRINCIPAL_NAME --query "[0].appId" -o tsv)

az identity federated-credential create \
  --name "ado-oidc-credential" \
  --identity-name /subscriptions/$SUBSCRIPTION_ID/resourceGroups/your-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$SERVICE_PRINCIPAL_NAME \
  --issuer "https://vstoken.dev.azure.com/" \
  --subject "org:$ADO_ORG:project:$ADO_PROJECT:ref:refs/heads/main"
```

### 2. Store Pipeline Variables in ADO

Create Pipeline Variables in Azure DevOps:

```
AZURE_SUBSCRIPTION_ID: f8a5f387-2f0b-42f5-b71f-5ee02b8967cf
AZURE_TENANT_ID: 38c7b18a-f92a-4353-a784-df16e895da23
AZURE_CLIENT_ID: <from service principal>
```

Mark `AZURE_CLIENT_ID` as **Secret** in the UI.

### 3. Create Service Connection in ADO

1. Go to **Project Settings** → **Service Connections**
2. **New Service Connection** → **Azure Resource Manager**
3. **Authentication Method**: Service Principal (OIDC)
4. **Tenant ID**: 38c7b18a-f92a-4353-a784-df16e895da23
5. **Subscription ID**: f8a5f387-2f0b-42f5-b71f-5ee02b8967cf
6. **Service Principal**: sp-terraform-ado-oidc
7. **Name**: `azure-terraform-connection`
8. **Grant access permission to all pipelines**: ✓

### 4. Configure Remote State Storage

The storage account `sttfstatedevd3120d7a` is already configured with:
- Resource Group: `rg-terraform-state-dev`
- Container: `terraform-state-dev`
- OIDC-only authentication (key-based auth disabled)

### 5. Run the Pipeline

1. Commit the `azure-pipelines.yml` file to your repository
2. Create a new pipeline in ADO pointing to this file
3. The pipeline will:
   - **Validate** Terraform code (hub and spoke)
   - **Plan** hub infrastructure
   - **Apply** hub infrastructure (after approval)
   - **Plan** spoke infrastructure
   - **Apply** spoke infrastructure (after approval)

## Pipeline Stages

### Stage 1: Validate
- Initializes Terraform for both hub and spoke
- Runs `terraform validate`
- Checks syntax without deployment

### Stage 2: PlanHub
- Plans hub infrastructure changes
- Publishes plan as artifact
- Shows what will be created/modified

### Stage 3: ApplyHub
- Requires environment approval
- Applies hub infrastructure
- Hub must succeed before spoke starts

### Stage 4: PlanSpoke
- Plans spoke infrastructure changes
- References hub outputs via `terraform_remote_state` data source
- Publishes plan as artifact

### Stage 5: ApplySpoke
- Requires environment approval
- Applies spoke infrastructure
- Uses hub outputs for firewall IP and DNS resolver

## Environment Approvals

Configure approvals in ADO:

1. Edit Pipeline → Environments
2. Create/select **production** environment
3. Add **Approval checks** to require manual review before apply stages

## Troubleshooting

### OIDC Token Not Working

**Error**: `Key based authentication is not permitted on this storage account`

**Solution**:
- Verify service principal has `Storage Blob Data Contributor` role on storage account
- Ensure `ARM_USE_OIDC=true` is set (already in pipeline)
- Check OIDC federated credential issuer and subject match ADO org/project

### State Lock Issues

If deployment is interrupted:

```bash
# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

### Remote State Not Found

Ensure:
- Storage account name matches: `sttfstatedevd3120d7a`
- Container name matches: `terraform-state-dev` or `terraform-state-prod`
- Key path matches: `hub-eastus/terraform.tfstate` or `spoke-aks-prod/terraform.tfstate`

## Best Practices

1. **Plan Review**: Always review plan output before approval
2. **Staged Rollout**: Deploy to dev/staging before production
3. **State Backups**: Storage account has versioning enabled
4. **Lock Prevention**: Never interrupt terraform operations
5. **Credential Rotation**: Rotate OIDC credentials regularly

## Local Testing

If testing locally with OIDC:

```bash
export ARM_USE_OIDC=true
export ARM_TENANT_ID=38c7b18a-f92a-4353-a784-df16e895da23
export ARM_CLIENT_ID=$(az ad sp list --display-name sp-terraform-ado-oidc --query "[0].appId" -o tsv)
export ARM_SUBSCRIPTION_ID=f8a5f387-2f0b-42f5-b71f-5ee02b8967cf

cd infra/terraform/hub-eastus
terraform init -backend-config="resource_group_name=rg-terraform-state-dev" \
  -backend-config="storage_account_name=sttfstatedevd3120d7a" \
  -backend-config="container_name=terraform-state-dev" \
  -backend-config="key=hub-eastus/terraform.tfstate" \
  -backend-config="use_oidc=true"

terraform plan -var-file=prod.tfvars
```

## Related Documentation

- [Terraform Azure Provider - OIDC](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs#authenticating-to-azure-with-the-azure-cli)
- [Azure DevOps - Workload Identity Federation](https://learn.microsoft.com/en-us/azure/devops/pipelines/release/azure-rm-endpoint?view=azure-devops)
- [Terraform Remote State - Azure Backend](https://developer.hashicorp.com/terraform/language/settings/backends/azurerm)

