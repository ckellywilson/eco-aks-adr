# GitHub Copilot Instruction Files Reference

This document provides an overview of all instruction files in this repository and how they are automatically applied by GitHub Copilot.

## How Instruction Files Work

GitHub Copilot automatically applies instruction files based on **file patterns**. When you edit a file that matches a pattern, Copilot loads the corresponding instruction file to guide code generation and suggestions.

### File Location

All instruction files are located in `.github/instructions/` and follow the naming convention:
```
<topic>.instructions.md
```

### Automatic Application

Each instruction file has YAML frontmatter that defines:
- `description`: Brief explanation of what the instruction covers
- `applyTo`: Glob pattern(s) that match files where this instruction should apply

Example:
```yaml
---
description: 'Guidelines for generating modern Terraform code for Azure'
applyTo: '**/*.tf'
---
```

## Instruction Files Overview

### 1. Terraform Infrastructure Code

#### `azure-verified-modules-terraform.instructions.md`
**Applies to**: `**/*.terraform`, `**/*.tf`, `**/*.tfvars`, `**/*.tfstate`, `**/*.tflint.hcl`, `**/*.tf.json`, `**/*.tfvars.json`

**Purpose**: Ensures generated Terraform code follows Azure Verified Modules (AVM) standards

**Key Topics**:
- Three-tiered validation approach (Pre-Commit, Pre-PR, CI/CD)
- AVM module discovery and usage
- Naming conventions for modules
- Version management and pinning
- Module sources (Terraform Registry and GitHub)

**When Applied**: Automatically when editing any Terraform file

#### `generate-modern-terraform-code-for-azure.instructions.md`
**Applies to**: `**/*.tf`

**Purpose**: Guidelines for generating modern, maintainable Terraform code for Azure

**Key Topics**:
- Latest Terraform and provider versions
- Clean code organization (main.tf, variables.tf, outputs.tf)
- Module encapsulation
- Variable and output best practices
- Provider selection (azurerm vs azapi)
- Idempotency and state management

**When Applied**: Automatically when editing Terraform `.tf` files

---

### 2. GitHub Actions Workflows

#### `github-actions-ci-cd-best-practices.instructions.md`
**Applies to**: `.github/workflows/*.yml`, `.github/workflows/*.yaml`

**Purpose**: Comprehensive guide for building robust, secure, and efficient CI/CD pipelines using GitHub Actions

**Key Topics**:
- Workflow structure and organization
- Jobs and steps best practices
- Security (secrets, OIDC, least privilege)
- Performance optimization (caching, matrix strategies)
- Testing integration (unit, integration, E2E)
- Deployment strategies

**When Applied**: Automatically when editing GitHub Actions workflow files

**Note**: For Terraform-specific workflows, see `github-actions-terraform-oidc.instructions.md`

#### `github-actions-terraform-oidc.instructions.md` ⭐ **NEW**
**Applies to**: 
- `.github/workflows/*terraform*.yml`
- `.github/workflows/*terraform*.yaml`
- `.github/workflows/*infra*.yml`
- `.github/workflows/*infra*.yaml`

**Purpose**: Specialized guide for Terraform deployments using OIDC authentication in GitHub Actions

**Key Topics**:
- OIDC federated identity configuration (Azure + GitHub)
- Workflow structure (Plan → Review → Apply pattern)
- State backend configuration with Azure Storage
- Environment-specific configuration
- Complete working example workflow
- Security best practices for Terraform deployments
- Troubleshooting common OIDC issues

**When Applied**: Automatically when editing GitHub Actions workflows with "terraform" or "infra" in the filename

**Cross-References**:
- `azure-verified-modules-terraform.instructions.md` for Terraform code standards
- `generate-modern-terraform-code-for-azure.instructions.md` for HCL patterns
- `github-actions-ci-cd-best-practices.instructions.md` for general workflow patterns

---

### 3. Azure DevOps Pipelines

#### `azure-devops-pipelines.instructions.md`
**Applies to**: `**/azure-pipelines.yml`, `**/azure-pipelines*.yml`, `**/*.pipeline.yml`

**Purpose**: Best practices for Azure DevOps Pipeline YAML files

**Key Topics**:
- Pipeline structure (stages, jobs, steps)
- Build best practices
- Testing integration
- Security considerations (Key Vault, service connections)
- Deployment strategies
- Variable and parameter management
- Performance optimization

**When Applied**: Automatically when editing Azure DevOps pipeline files

**Note**: For Terraform-specific pipelines, see `ado-terraform-oidc.instructions.md`

#### `ado-terraform-oidc.instructions.md`
**Applies to**: `**/azure-pipelines.yml`, `**/azure-pipelines*.yml` (Terraform projects)

**Purpose**: Azure DevOps pipeline generation for Terraform deployments with OIDC authentication

**Key Topics**:
- OIDC federated identity configuration (Azure + ADO)
- Pipeline structure (Validate → Plan → Apply pattern)
- State backend configuration
- Variable groups for environment-specific config
- Complete working example pipeline
- Security best practices
- Troubleshooting ADO-specific issues

**When Applied**: Automatically when editing Azure DevOps pipeline files in Terraform projects

**Cross-References**:
- `azure-verified-modules-terraform.instructions.md` for Terraform standards
- `generate-modern-terraform-code-for-azure.instructions.md` for code generation
- `azure-devops-pipelines.instructions.md` for general pipeline patterns

---

## File Pattern Coverage Map

This table shows which instruction files apply to common file types:

| File Type | Example Path | Applied Instructions |
|-----------|--------------|---------------------|
| Terraform code | `hub/main.tf` | `azure-verified-modules-terraform.instructions.md`<br>`generate-modern-terraform-code-for-azure.instructions.md` |
| Terraform variables | `spoke-aks/variables.tfvars` | `azure-verified-modules-terraform.instructions.md` |
| GitHub Actions workflow | `.github/workflows/ci.yml` | `github-actions-ci-cd-best-practices.instructions.md` |
| GitHub Actions Terraform | `.github/workflows/terraform-deploy.yml` | `github-actions-ci-cd-best-practices.instructions.md`<br>`github-actions-terraform-oidc.instructions.md` |
| GitHub Actions Infrastructure | `.github/workflows/infra-plan.yaml` | `github-actions-ci-cd-best-practices.instructions.md`<br>`github-actions-terraform-oidc.instructions.md` |
| Azure DevOps pipeline | `azure-pipelines.yml` | `azure-devops-pipelines.instructions.md`<br>`ado-terraform-oidc.instructions.md` (if Terraform) |
| ADO pipeline variant | `pipelines/terraform.pipeline.yml` | `azure-devops-pipelines.instructions.md`<br>`ado-terraform-oidc.instructions.md` (if Terraform) |

---

## Using Instructions Explicitly

While instruction files are automatically applied based on file patterns, you can also reference them explicitly in your prompts:

```
# In GitHub Copilot Chat

"Generate Terraform code following @instructions/azure-verified-modules-terraform.instructions.md"

"Create a GitHub Actions workflow following @instructions/github-actions-terraform-oidc.instructions.md"

"Review this pipeline against @instructions/ado-terraform-oidc.instructions.md"
```

---

## Adding New Instruction Files

To add a new instruction file:

1. Create a file in `.github/instructions/` with the naming pattern: `<topic>.instructions.md`

2. Add YAML frontmatter at the top:
```yaml
---
description: 'Brief description of what this instruction covers'
applyTo: '<glob-pattern-for-files>'
---
```

3. Write comprehensive instructions following the pattern of existing files

4. Test with sample files to ensure the pattern matching works

5. Update this reference document

---

## Validation

To validate all instruction files have proper frontmatter:

```bash
# Run the validation script
python3 << 'EOF'
import os, re, glob

for file_path in glob.glob('.github/instructions/*.instructions.md'):
    with open(file_path, 'r') as f:
        content = f.read()
    
    match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
    if not match:
        print(f"❌ {os.path.basename(file_path)}: No frontmatter")
        continue
    
    frontmatter = match.group(1)
    has_description = 'description:' in frontmatter
    has_applyTo = 'applyTo:' in frontmatter
    
    status = "✅" if (has_description and has_applyTo) else "⚠️ "
    print(f"{status} {os.path.basename(file_path)}")
EOF
```

Expected output:
```
✅ ado-terraform-oidc.instructions.md
✅ azure-devops-pipelines.instructions.md
✅ azure-verified-modules-terraform.instructions.md
✅ generate-modern-terraform-code-for-azure.instructions.md
✅ github-actions-ci-cd-best-practices.instructions.md
✅ github-actions-terraform-oidc.instructions.md
```

---

## Related Documentation

- **Workflow Instructions**: `.github/copilot-instructions.md` - General GitHub Copilot workflow and development process
- **AVM Documentation**: [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/)
- **GitHub Copilot Docs**: [Custom Instructions](https://docs.github.com/en/copilot/customizing-copilot/adding-custom-instructions-for-github-copilot)

---

## Summary

✅ **6 instruction files** covering:
- Terraform code generation (2 files)
- GitHub Actions workflows (2 files)
- Azure DevOps pipelines (2 files)

✅ All files have proper YAML frontmatter with `description` and `applyTo` patterns

✅ Comprehensive coverage for infrastructure-as-code and CI/CD workflows

✅ Cross-referenced for consistent guidance across related topics
