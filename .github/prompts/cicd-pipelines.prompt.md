# CI/CD Pipeline Generation Prompt

Generate CI/CD pipelines for Terraform infrastructure deployment with the following requirements:

⚠️ **CONFIGURATION REQUIRED**

Before generating pipelines, specify your CI/CD platform and requirements:

```yaml
# ============================================================================
# CI/CD PLATFORM SELECTION
# ============================================================================
cicd_platform: "[DECISION REQUIRED: github-actions | azure-devops]"

# ============================================================================
# INFRASTRUCTURE TARGETS
# ============================================================================
deploy_hub: [DECISION REQUIRED: true | false]
deploy_spoke: [DECISION REQUIRED: true | false]

# ============================================================================
# ENVIRONMENT CONFIGURATION
# ============================================================================
environments:
  - name: "dev"
    requires_approval: false
    auto_deploy: true
  - name: "prod"
    requires_approval: true
    auto_deploy: false

# ============================================================================
# TERRAFORM BACKEND
# ============================================================================
backend_type: "azurerm"
backend_resource_group: "[DECISION REQUIRED: rg-terraform-state]"
backend_storage_account: "[DECISION REQUIRED: sttfstate<unique>]"
backend_container: "tfstate"

# ============================================================================
# AZURE AUTHENTICATION
# ============================================================================
# GitHub Actions: Uses OIDC with Federated Credentials (recommended)
# Azure DevOps: Uses Service Connection
auth_method: "[DECISION REQUIRED: oidc | service-principal]"
```

---

## Example Configurations

### Example 1: GitHub Actions for Full Stack Deployment

```yaml
# Production-ready GitHub Actions configuration
cicd_platform: "github-actions"
deploy_hub: true
deploy_spoke: true

environments:
  - name: "dev"
    requires_approval: false
    auto_deploy: true
  - name: "prod"
    requires_approval: true
    auto_deploy: false

backend_type: "azurerm"
backend_resource_group: "rg-tfstate-prod-eastus2"
backend_storage_account: "sttfstate20260121"
backend_container: "tfstate"

auth_method: "oidc"
```

**Use Case**: Team using GitHub for source control, deploying both hub and spoke infrastructure with production approval gates.

---

### Example 2: Azure DevOps for Spoke-Only Deployment

```yaml
# Development environment using Azure DevOps
cicd_platform: "azure-devops"
deploy_hub: false
deploy_spoke: true

environments:
  - name: "dev"
    requires_approval: false
    auto_deploy: true

backend_type: "azurerm"
backend_resource_group: "rg-tfstate-dev-westus"
backend_storage_account: "sttfstatedev98765"
backend_container: "tfstate"

auth_method: "oidc"
```

**Use Case**: Platform team manages hub infrastructure separately, application teams deploy only spoke using Azure DevOps.

---

### Example 3: Multi-Environment GitHub Actions

```yaml
# Multi-environment deployment with staging
cicd_platform: "github-actions"
deploy_hub: true
deploy_spoke: true

environments:
  - name: "dev"
    requires_approval: false
    auto_deploy: true
  - name: "staging"
    requires_approval: true
    auto_deploy: false
  - name: "prod"
    requires_approval: true
    auto_deploy: false

backend_type: "azurerm"
backend_resource_group: "rg-tfstate-global"
backend_storage_account: "sttfstatemultienv"
backend_container: "tfstate"

auth_method: "oidc"
```

**Use Case**: Enterprise setup with dev → staging → prod promotion workflow.

---

### Example 4: Azure DevOps with Service Principal (Legacy)

```yaml
# Legacy configuration using service principal
cicd_platform: "azure-devops"
deploy_hub: true
deploy_spoke: false

environments:
  - name: "prod"
    requires_approval: true
    auto_deploy: false

backend_type: "azurerm"
backend_resource_group: "rg-tfstate-legacy"
backend_storage_account: "sttfstatelegacy123"
backend_container: "tfstate"

auth_method: "service-principal"
```

**Use Case**: Existing infrastructure using service principal authentication (migration to OIDC recommended).

---

## Pipeline Requirements

### Common Requirements (Both Platforms)

1. **Validation Stage** (runs on all PRs)
   - `terraform fmt -check -recursive`
   - `terraform init`
   - `terraform validate`
   - Security scanning (tfsec or checkov)
   - AVM compliance checks

2. **Plan Stage** (runs on PRs and before apply)
   - `terraform plan -out=tfplan`
   - Post plan output as PR comment
   - Store plan artifact for apply stage

3. **Apply Stage** (runs on merge to main)
   - Download plan artifact
   - `terraform apply tfplan`
   - Environment-specific deployment
   - Approval gates for production

4. **Destroy Stage** (manual trigger only)
   - Requires explicit confirmation
   - Environment protection rules

---

## GitHub Actions Requirements

If `cicd_platform: github-actions`, generate the following workflow files:

### File Structure
```
.github/
└── workflows/
    ├── terraform-validate.yml      # PR validation
    ├── terraform-plan.yml          # Plan on PR
    ├── terraform-apply.yml         # Apply on merge
    ├── terraform-destroy.yml       # Manual destroy
    └── _reusable-terraform.yml     # Reusable workflow
```

### GitHub Actions Specific Features

1. **OIDC Authentication** (recommended)
   ```yaml
   permissions:
     id-token: write
     contents: read
     pull-requests: write
   ```

2. **Environment Protection**
   - Use GitHub Environments for approval gates
   - Configure environment secrets per environment
   - Use `environment:` keyword for deployments

3. **Concurrency Control**
   ```yaml
   concurrency:
     group: terraform-${{ github.workflow }}-${{ github.ref }}
     cancel-in-progress: false
   ```

4. **PR Comments**
   - Post terraform plan as collapsible comment
   - Update existing comment on subsequent runs
   - Include validation results

5. **Artifacts**
   - Upload tfplan as artifact
   - Retain for apply job
   - Set appropriate retention period

### Required GitHub Secrets/Variables

```yaml
# Repository Secrets (or Environment Secrets)
AZURE_CLIENT_ID: "..."           # For OIDC
AZURE_TENANT_ID: "..."           # For OIDC  
AZURE_SUBSCRIPTION_ID: "..."     # For OIDC

# Or for Service Principal
ARM_CLIENT_ID: "..."
ARM_CLIENT_SECRET: "..."
ARM_TENANT_ID: "..."
ARM_SUBSCRIPTION_ID: "..."

# Repository Variables
TF_STATE_RESOURCE_GROUP: "rg-terraform-state"
TF_STATE_STORAGE_ACCOUNT: "sttfstate..."
TF_STATE_CONTAINER: "tfstate"
```

---

## Azure DevOps Pipelines Requirements

If `cicd_platform: azure-devops`, generate the following pipeline files:

### File Structure
```
.azdo/
├── pipelines/
│   ├── terraform-validate.yml     # PR validation
│   ├── terraform-deploy.yml       # Full deployment pipeline
│   ├── terraform-destroy.yml      # Manual destroy
│   └── templates/
│       ├── terraform-init.yml     # Reusable init template
│       ├── terraform-plan.yml     # Reusable plan template
│       └── terraform-apply.yml    # Reusable apply template
└── README.md                      # Setup instructions
```

### Azure DevOps Specific Features

1. **Service Connections**
   - Use Azure Resource Manager service connection
   - Workload Identity Federation (recommended)
   - Or Service Principal with secret

2. **Environments**
   - Define environments in Azure DevOps
   - Configure approval gates
   - Use `deployment` jobs for tracking

3. **Variable Groups**
   - Environment-specific variable groups
   - Link to Azure Key Vault for secrets

4. **Pipeline Triggers**
   ```yaml
   trigger:
     branches:
       include:
         - main
     paths:
       include:
         - 'hub/**'
         - 'spoke-aks/**'
   
   pr:
     branches:
       include:
         - main
   ```

5. **Stages Structure**
   - Validate → Plan → Apply (with approval)
   - Environment-specific stages
   - Conditional execution

### Required Azure DevOps Configuration

```yaml
# Service Connection
service_connection: "azure-terraform-sp"

# Variable Groups
variable_groups:
  - "terraform-common"      # Backend config
  - "terraform-dev"         # Dev environment
  - "terraform-prod"        # Prod environment

# Environments (create in Azure DevOps)
environments:
  - name: "dev"
    approvers: []
  - name: "prod"
    approvers: ["platform-team"]
```

---

## Pipeline Logic

### Validation Workflow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Checkout  │ ──► │ Terraform   │ ──► │  Security   │
│             │     │ fmt/validate│     │    Scan     │
└─────────────┘     └─────────────┘     └─────────────┘
                                               │
                                               ▼
                                        ┌─────────────┐
                                        │  Post PR    │
                                        │  Comment    │
                                        └─────────────┘
```

### Deployment Workflow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│    Plan     │ ──► │   Upload    │ ──► │  Approval   │ ──► │   Apply     │
│             │     │  Artifact   │     │   (prod)    │     │             │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
```

---

## Security Requirements

1. **Secrets Management**
   - Never store secrets in pipeline files
   - Use platform-native secret management
   - Rotate credentials regularly

2. **Least Privilege**
   - Use minimal required permissions
   - Separate service principals per environment
   - Limit who can trigger production deployments

3. **State Protection**
   - Enable state locking
   - Use private endpoints for storage (if possible)
   - Enable soft delete on storage account

4. **Audit Trail**
   - Enable pipeline run retention
   - Log all terraform operations
   - Integrate with Azure Activity Logs

---

## Output Structure

### For GitHub Actions
Generate files in `.github/workflows/` directory with:
- Proper YAML syntax and formatting
- Comments explaining each section
- Placeholder values clearly marked
- Setup instructions in workflow comments

### For Azure DevOps
Generate files in `.azdo/pipelines/` directory with:
- Proper YAML syntax for Azure Pipelines
- Template references for reusability
- README.md with setup instructions
- Variable group configuration guide

---

## Post-Generation Steps

After generating pipelines, remind the user to:

1. **Configure Authentication**
   - Set up OIDC/Service Principal
   - Create service connections
   - Configure secrets/variables

2. **Create Environments**
   - Set up GitHub Environments or Azure DevOps Environments
   - Configure approval gates

3. **Update Backend Configuration**
   - Create storage account for state
   - Configure container and access

4. **Test Pipeline**
   - Create test branch
   - Open PR to validate workflow
   - Verify plan output
