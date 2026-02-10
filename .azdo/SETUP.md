# Azure DevOps Terraform Pipeline Setup Guide

> **Based on Microsoft Official Best Practices**
> https://learn.microsoft.com/en-us/azure/developer/terraform/best-practices-integration-testing

## 🔴 Critical Issues Fixed

The previous pipeline had several issues that prevented it from working:

### 1. ❌ Incorrect Authentication Method
- **Old**: Used `ARM_USE_AZUREAD=true` for unattended pipeline execution
- **Problem**: This requires interactive authentication, not suitable for CI/CD
- **New**: Uses Azure DevOps Service Connection with access key delegation

### 2. ❌ Missing Service Connection
- **Old**: Used raw Azure subscription ID
- **Problem**: No proper credential management or RBAC delegation
- **New**: Uses Azure DevOps Service Connections with proper credential handling

### 3. ❌ State Backend Configuration
- **Old**: No explicit access key retrieval
- **Problem**: Default authentication method was insufficient
- **New**: Explicitly retrieves storage account access key via Azure CLI

### 4. ❌ State Locking Issues
- **Old**: No timeout handling
- **Problem**: State locks from failed runs persisted
- **New**: Proper error handling and `-input=false -upgrade=true` flags

### 5. ❌ No Static Analysis
- **Old**: Direct plan and apply
- **Problem**: Security issues and syntax errors caught too late
- **New**: `terraform fmt`, `terraform validate`, and `tfsec` run first

## ✅ What's Fixed Now

- ✅ **Service Connection-based authentication** (Microsoft recommended)
- ✅ **Proper state backend configuration** with explicit access key
- ✅ **Four-stage pipeline**: Validate → Init → Plan → Apply
- ✅ **Static code analysis** with formatting and security checks
- ✅ **Proper error handling** and exit codes
- ✅ **Environment-based approvals** for production deployments
- ✅ **TF_IN_AUTOMATION=true** to disable interactive prompts

## 🔧 Required Setup in Azure DevOps

### Step 1: Create Service Principal (Azure CLI)

```bash
# Create a service principal for Terraform
SUBSCRIPTION_ID="f8a5f387-2f0b-42f5-b71f-5ee02b8967cf"

az ad sp create-for-rbac \
  --name terraform-pipeline \
  --role Contributor \
  --scopes /subscriptions/$SUBSCRIPTION_ID
```

**Output should include:**
- `appId` (use as CLIENT_ID)
- `password` (use as CLIENT_SECRET)
- `tenant` (use as TENANT_ID)

### Step 2: Create Azure Service Connection in Azure DevOps

1. **Navigate to**: Project Settings → Service Connections → New Service Connection
2. **Select**: Azure Resource Manager
3. **Authentication Method**: Service Principal (manual)
4. **Fill in**:
   - Subscription Name: `Azure-Terraform-Connection`
   - Subscription ID: `f8a5f387-2f0b-42f5-b71f-5ee02b8967cf`
   - Service Principal ID: (from Step 1 `appId`)
   - Service Principal Key: (from Step 1 `password`)
   - Tenant ID: (from Step 1 `tenant`)
5. **Grant Access**: Check "Grant access permission to all pipelines"

⚠️ **Important**: Service connection name must be `Azure-Terraform-Connection` (matches pipeline variable)

### Step 3: Configure Storage Account for RBAC

The Terraform state backend **MUST** be configured for RBAC authentication only (no shared access keys):

```bash
STORAGE_ACCOUNT="sttfstatedevd3120d7a"
RESOURCE_GROUP="rg-terraform-state-dev"
SERVICE_PRINCIPAL_ID="<your-service-principal-app-id>"

# 1. Disable shared access keys and enable public blob access
az storage account update \
  --resource-group $RESOURCE_GROUP \
  --name $STORAGE_ACCOUNT \
  --allow-shared-key-access false \
  --default-action Allow

# 2. Grant Storage Blob Data Contributor role to service principal
az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee $SERVICE_PRINCIPAL_ID \
  --scope /subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT

# 3. Verify configuration
az storage account show \
  --resource-group $RESOURCE_GROUP \
  --name $STORAGE_ACCOUNT \
  --query "{allowBlobPublicAccess:allowBlobPublicAccess, allowSharedKeyAccess:allowSharedKeyAccess}" -o table
```

**Expected Output:**
```
AllowBlobPublicAccess    AllowSharedKeyAccess
True                     False
```

✅ **Key Configuration:**
- Public blob access **ENABLED** (allowBlobPublicAccess = true)
- Shared access keys **DISABLED** (authentication via RBAC only)
- Service principal has `Storage Blob Data Contributor` role

### Step 4: Verify Storage Backend

Verify your backend storage account is accessible via RBAC:

```bash
# Verify storage account exists
az storage account show \
  --resource-group rg-terraform-state-dev \
  --name sttfstatedevd3120d7a \
  --query "{name:name, allowBlobPublicAccess:allowBlobPublicAccess}" -o table

# Verify the container exists
az storage container exists \
  --account-name sttfstatedevd3120d7a \
  --container-name terraform-state-dev \
  --auth-mode login

# List state files
az storage blob list \
  --account-name sttfstatedevd3120d7a \
  --container-name terraform-state-dev \
  --auth-mode login
```

### Step 5: Create Azure DevOps Environments

For production deployments, environments provide approval gates:

1. **Hub-Production**
   - Navigate to: Pipelines → Environments
   - Create new environment named `Hub-Production`
   - Add approvers if desired

2. **Spoke-Production**
   - Create new environment named `Spoke-Production`
   - Add approvers if desired

## 🚀 Testing the Pipeline

### Test 1: Run Validate Stage
```bash
# Create a feature branch
git checkout -b test/pipeline-validation

# Make a small change (e.g., update comment in main.tf)
git add .
git commit -m "test: validate pipeline"
git push -u origin test/pipeline-validation

# Create PR in Azure DevOps - this should trigger validation
```

Expected result: ✅ Validate stage passes

### Test 2: Run Full Pipeline
```bash
# Create a production-ready branch
git checkout -b feature/pipeline-test

# Make infrastructure change
git add .
git commit -m "feat: test pipeline apply"
git push -u origin feature/pipeline-test

# Merge to main to trigger full pipeline
```

Expected stages:
1. ✅ Validate (format, syntax, security)
2. ✅ Init (initialize backend)
3. ✅ Plan (generate execution plan)
4. ✅ Apply (with environment approval)

## 🔐 Security Best Practices

### What NOT to Do
- ❌ Don't commit `.tfstate` or `.tfstate.backup` files
- ❌ Don't store credentials in pipeline YAML
- ❌ Don't use `ARM_USE_AZUREAD=true` for unattended runs
- ❌ Don't hardcode subscription IDs in most places
- ❌ Don't share access keys

### What to Do
- ✅ Use Service Connections for all authentication
- ✅ Store sensitive values in Key Vault (advanced setup)
- ✅ Use separate service accounts per environment
- ✅ Enable state locking in backend
- ✅ Use RBAC to restrict service principal permissions
- ✅ Regularly review and rotate credentials

## 🛠️ Variable Configuration

### Pipeline Variables (in YAML)

```yaml
variables:
  terraformVersion: '1.9'                    # Terraform version to use
  azureServiceConnection: 'Azure-Terraform-Connection'  # Must match ADO service connection
  backendResourceGroup: 'rg-terraform-state'  # Where state storage lives
  backendStorageAccount: 'tfstate'            # Storage account name
  backendContainer: 'terraform'               # Container in storage account
```

### Environment Variables (Created by Tasks)

- `BACKEND_ACCESS_KEY` - Retrieved from storage account at runtime
- `TF_INPUT=false` - Disable interactive prompts
- `TF_IN_AUTOMATION=true` - Optimize for automation

## 🐛 Troubleshooting

### Error: "Error acquiring the state lock"

**Cause**: State blob is locked from previous run

**Solution**:
```bash
# Using Azure Storage Browser:
# 1. Go to Azure Portal
# 2. Open storage account "tfstate"
# 3. Go to container "terraform" 
# 4. Find blob "hub-eastus.tfstate.lock" or "spoke-aks-prod.tfstate.lock"
# 5. Click "..." → "Break Lease"

# Or using Azure CLI:
az storage blob lease break \
  --account-name tfstate \
  --container-name terraform \
  --blob-name "hub-eastus.tfstate.lock"
```

### Error: "Unable to list provider registration status"

**Cause**: Service principal doesn't have rights or wrong subscription

**Solution**:
```bash
# Verify service connection can access subscription
SUBSCRIPTION_ID="f8a5f387-2f0b-42f5-b71f-5ee02b8967cf"

az account set --subscription $SUBSCRIPTION_ID
az provider list --query "[?registrationState=='Registered']" -o table

# Grant service principal access if needed
az role assignment create \
  --role Contributor \
  --assignee <service-principal-app-id> \
  --subscription $SUBSCRIPTION_ID
```

### Error: "RBAC authorization failed" or "Insufficient permissions"

**Cause**: Service principal doesn't have Storage Blob Data Contributor role on storage account

**Solution**:
```bash
SERVICE_PRINCIPAL_ID="<your-service-principal-app-id>"
STORAGE_ACCOUNT="sttfstatedevd3120d7a"
RESOURCE_GROUP="rg-terraform-state-dev"

# Grant Storage Blob Data Contributor role
az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee $SERVICE_PRINCIPAL_ID \
  --scope /subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT

# Verify role assignment
az role assignment list \
  --assignee $SERVICE_PRINCIPAL_ID \
  --scope /subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT
```

### Error: "Shared access keys are disabled"

**Cause**: Storage account has shared access keys disabled (expected), but pipeline is trying to use access key

**Solution**: 
This error should not occur - the updated pipelines use RBAC via Azure CLI. If you see this:
1. Ensure pipelines are using latest templates
2. Verify `ARM_USE_AZUREAD: true` is set in all pipeline steps
3. Re-run the pipeline

### Plan shows unexpected changes

**Cause**: Local state doesn't match remote

**Solution**:
```bash
# Refresh state from Azure
cd infra/terraform/hub-eastus
terraform refresh -var-file="prod.tfvars"
```

## 📊 Pipeline Stages Explained

### Validate Stage
```yaml
- terraform fmt -check       # Check code formatting
- terraform init -backend=false  # Validate syntax only
- terraform validate         # Check configuration validity
- tfsec                       # Security scanning
```

### Init Stage
```yaml
- Verify storage account access via RBAC
- terraform init                 # Initialize backend state using Azure CLI auth
```

### Plan Stage
```yaml
- terraform init              # Re-initialize for plan
- terraform plan              # Generate execution plan
- Artifact published          # Save plan for apply stage
```

### Apply Stage (Manual Approval)
```yaml
- terraform init              # Initialize
- terraform plan              # Verify no changes
- terraform apply             # Apply the plan
- Output published            # Save outputs
```

## 📝 Next Steps

## 📝 Next Steps

1. **Create Service Principal** (Step 1 above)
2. **Create Service Connection in Azure DevOps** (Step 2)
3. **Configure Storage Account for RBAC** (Step 3) ← **CRITICAL**
4. **Verify Storage Backend** (Step 4)
5. **Create Environments** (Step 5)
6. **Test with feature branch** (Testing section)
7. **Monitor pipeline runs** in Azure DevOps UI

⚠️ **Step 3 is mandatory** - Storage account MUST be RBAC-only with shared access keys disabled and public blob access enabled.

## 🔗 References

- [Microsoft: Terraform Best Practices](https://learn.microsoft.com/en-us/azure/developer/terraform/best-practices-integration-testing)
- [Microsoft: Troubleshooting Terraform](https://learn.microsoft.com/en-us/azure/developer/terraform/troubleshoot)
- [Microsoft: Store State in Azure Storage](https://learn.microsoft.com/en-us/azure/developer/terraform/store-state-in-azure-storage)
- [Azure DevOps: Service Connections](https://learn.microsoft.com/en-us/azure/devops/pipelines/library/connect-to-azure)
- [Terraform: Azure Provider Auth](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs#authenticating-to-azure)

## 📞 Support

If issues persist:
1. Check Azure DevOps pipeline logs (full output)
2. Verify service connection is working: Settings → Service Connections → Test connection
3. Check service principal permissions in Azure Portal
4. Review storage account access logs in Azure Portal
