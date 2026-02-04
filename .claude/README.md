# GitHub Agent Skills - Quick Reference

**Location**: `.claude/skills/`

This repository includes GitHub Agent Skills that automate Azure infrastructure-as-code generation. Skills work automatically with GitHub Copilot agent mode.

## 🚀 Quick Commands

| What You Want | Say This | Skill Activated |
|---------------|----------|-----------------|
| Generate infrastructure | "Generate Terraform from my JSON" | terraform/generate-from-json |
| Check code quality | "Validate my Terraform code" | validate-terraform |

## 📋 Typical Workflow

```bash
# 1. Create flexible JSON configuration
# Engineer creates JSON with metadata, globalConstraints, topology (hubs[], spokes[]), aksDesign

# 2. Generate infrastructure
"Generate Terraform from this JSON"
# Creates hub-{name}/ and spoke-{name}/ folders with Terraform code

# 3. Validate generated code
"Validate my Terraform code"

# 4. Deploy infrastructure (manual)
cd infra/terraform/hub-eastus && ./deploy.sh dev
cd infra/terraform/spoke-aks-prod && ./deploy.sh dev
```

## 📚 Full Documentation

See [.claude/skills/README.md](.claude/skills/README.md) for complete documentation.

## 🎯 Available Skills

### 1. **terraform/generate-from-json**
**Trigger**: "Generate Terraform from my JSON"  
**Purpose**: Generates Terraform infrastructure code from flexible JSON schema

**What it does:**
- Reads flexible JSON with multiple hubs and spokes
- Creates segregated folders: `hub-{name}/`, `spoke-{name}/`
- Generates provider aliases for multi-subscription support
- Applies Azure Verified Modules (AVM) standards
- Creates hub outputs in `{hub-name}-outputs.json`
- Spokes consume hub outputs via `jsondecode(file(...))`
- Supports default resources per spoke type (aks, data, integration, sharedServices, other)

### 2. **validate-terraform**
**Trigger**: "Validate my Terraform code"  
**Purpose**: Validates Terraform code against AVM standards

**What it does:**
- Runs `terraform fmt` and `terraform validate`
- Checks AVM module compliance
- Verifies version pinning and telemetry settings
- Runs security scans (if available)
- Provides actionable feedback

## 🎯 What Are Skills?

Skills are automation instructions that Copilot loads automatically when you ask for something
- Follow workflows

## 💡 First Time Setup

Before generating infrastructure:

1. **Fork/clone this template**
2. **Run**: `"Help me customize the prompts"`
3. **Complete decision guide** (Copilot will guide you)
4. **Generate infrastructure**

## 🔧 Requirements

- GitHub Copilot with agent mode (VS Code Insiders or stable with agent support)
- Terraform installed locally
- Azure CLI (for deployment)

## ❓ Need Help?

- **Skills not working?** Check [Troubleshooting](.claude/skills/README.md#-troubleshooting)
- **Configuration questions?** Run: `"Help me customize the prompts"`
- **Validation errors?** Check [.github/instructions/](../.github/instructions/)

---

**Start here**: `"Help me customize the prompts"`
