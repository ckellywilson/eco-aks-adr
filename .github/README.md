# About This Repository

This repository provides an **AKS Landing Zone** implementation that leverages **GitHub Copilot (GHCP)** as an AI-powered infrastructure-as-code generation engine. Rather than providing pre-built Terraform modules, this repository contains carefully crafted prompts, instructions, and documentation that guide GitHub Copilot to generate production-ready Terraform code following Azure Verified Modules (AVM) standards and Azure best practices. This approach enables you to rapidly deploy enterprise-grade AKS environments with hub-spoke networking, Azure Firewall egress control, and flexible governance models—all generated on-demand by AI.

## Deployment Scenarios

The repository supports four primary deployment scenarios based on your organization's governance model:

- **Scenario 1: Full Application Team Autonomy** - Teams create and manage all infrastructure (ideal for dev/test)
- **Scenario 2: Platform-Provided Networking** ⭐ **Recommended for Production** - Platform team provides networking, application teams deploy workloads
- **Scenario 3: Hybrid Model** - Shared responsibility between platform and application teams
- **Scenario 4: Security-First Model** - Maximum security with egress restriction enforced at infrastructure layer

Each scenario has security variants (**Standard** or **Egress-Restricted**) to match your compliance requirements. See [deployment-scenarios.md](docs/deployment-scenarios.md) for detailed guidance.

---

# .github Directory Structure

This directory contains GitHub-specific configuration, Copilot prompts, documentation, and testing guides for the AKS Landing Zone project.

## Directory Overview

```
.github/
├── prompts/              # GitHub Copilot code generation prompts
├── docs/                 # User documentation and decision guides
├── demos/                # Testing and validation guides
└── instructions/         # Copilot auto-applied instructions for code editing
```

---

## 📝 Prompts (Terraform Code Patterns)

**Location:** `.github/prompts/terraform/`

Terraform code pattern templates referenced by skills when generating infrastructure.

| File | Purpose | Referenced By |
|------|---------|---------------|
| `infrastructure.prompt.md` | AVM module patterns for hubs, spokes (all types), providers, outputs | `terraform/generate-from-json` skill |

**How it works:**
1. Engineer creates flexible JSON configuration
2. Engineer asks: "Generate Terraform from my JSON"
3. Skill reads JSON and references infrastructure.prompt.md for code patterns
4. Generates segregated folders: hub-{name}/, spoke-{name}/

---

## 📚 Documentation (for Humans)

**Location:** `.github/docs/`

Decision guides and reference documentation to help you choose the right configuration.

| File | Purpose | When to Read |
|------|---------|--------------|
| `deployment-scenarios.md` | Comprehensive guide to 4 deployment scenarios (who creates what) and security posture variants (standard vs egress-restricted) | **BEFORE** generating infrastructure code - helps you decide which variables to use |
| `aks-configuration-decisions.md` ⭐ **NEW** | AKS network configuration guide: Network plugin (Azure CNI Overlay/Standard), data plane (Cilium), network policy, and outbound type selection with Microsoft recommendations | **REQUIRED BEFORE** generating AKS spoke code - complete ALL decisions first |
| `aks-configuration-quick-reference.md` ⭐ **NEW** | Quick lookup for configuration options, compatibility matrix, common patterns, and CLI examples | Quick reference during implementation |

**Key Scenarios:**
- **Scenario 1**: Full Application Team Autonomy
- **Scenario 2**: Platform-Provided Networking (BYO VNet) ⭐ **Recommended for Production**
- **Scenario 3**: Hybrid Model
- **Scenario 4**: Security-First Model (Egress Restricted)

**Each scenario has variants:**
- **Variant A**: Standard Security (permissive egress)
- **Variant B**: Egress-Restricted Security (force tunnel via Azure Firewall)

**AKS Network Configuration Options:** Based on official Microsoft documentation (January 2026)
- **Network Plugin**: Azure CNI Overlay ⭐ (Microsoft recommended) or Azure CNI Standard
- **Data Plane**: Azure CNI Powered by Cilium ⭐ (Microsoft recommended) or Azure IPTables
- **Network Policy**: Cilium ⭐ (built-in with Cilium), Azure NPM, or Calico
- **Outbound Type**: userDefinedRouting (egress restriction), loadBalancer, or NAT Gateway

---

## 🧪 Demos (for Testing & Validation)

**Location:** `.github/demos/`

Hands-on testing guides to validate deployed infrastructure.

| File | Purpose | When to Use |
|------|---------|-------------|
| `egress-restriction-demo.md` | Comprehensive demo showing AKS egress restriction using Azure Firewall - compares non-restricted vs egress-restricted configurations | **AFTER** deploying infrastructure - validates security controls are working |

**What's Included:**
- Step-by-step deployment procedures
- Test workloads and validation scripts
- Azure Firewall rule configuration
- Troubleshooting guide
- Ready-to-use presentation scripts (5-min executive + 15-min technical)

---

## 🔧 Instructions (Auto-Applied by Copilot)

**Location:** `.github/instructions/`

Automatically applied when editing files matching specific patterns.

| File | Applied To | Purpose |
|------|------------|---------|
| `azure-verified-modules-terraform.instructions.md` | `**/*.tf`, `**/*.tfvars` | Ensures generated Terraform code follows Azure Verified Modules (AVM) standards |
| `generate-modern-terraform-code-for-azure.instructions.md` | `**/*.tf` | Azure-specific Terraform best practices and conventions |
| `github-actions-ci-cd-best-practices.instructions.md` | `.github/workflows/*.yml` | GitHub Actions workflow best practices |
| `github-actions-terraform-oidc.instructions.md` ⭐ | `.github/workflows/*terraform*.yml` | GitHub Actions Terraform deployments with OIDC |
| `azure-devops-pipelines.instructions.md` | `**/azure-pipelines.yml` | Azure DevOps pipeline best practices |
| `ado-terraform-oidc.instructions.md` | `**/azure-pipelines.yml` (Terraform) | ADO Terraform deployments with OIDC |

📖 **See [INSTRUCTION_FILES.md](INSTRUCTION_FILES.md) for complete documentation of all instruction files, patterns, and usage.**

**How It Works:**
- Instructions are **automatically read** when you edit matching files (e.g., `*.tf`)
- Copilot uses these rules when generating or modifying code
- You can reference instructions explicitly: `@instructions/azure-verified-modules-terraform.instructions.md`
- No manual action required for auto-application

**Example Flow:**
1. You edit `main.tf` (matches `**/*.tf` pattern)
2. Copilot automatically loads relevant instruction files
3. Your code generation follows AVM standards and Azure best practices
4. Verify compliance by asking: "Does this code follow the AVM instructions?"

---

## 🚀 Quick Start Workflow

### Quick Decision Guide

**Choose Your Deployment Scenario:**

- **👨‍💻 Dev/Test + Full Control** → Scenario 1A (Full autonomy, standard security)
- **🏢 Enterprise Production** → Scenario 2B (Platform networking, egress restricted) ⭐ **RECOMMENDED**
- **🔄 Transitioning Governance** → Scenario 3A (Hybrid model, standard security)
- **🔒 Maximum Security** → Scenario 4 (Same as 2B with additional SecOps controls)

```bash
# Step 1: Read deployment scenarios
cat .github/docs/deployment-scenarios.md

# Step 2: Complete AKS configuration decisions (REQUIRED)
code .github/docs/aks-configuration-decisions.md

# Step 3: Review example configurations
ls .github/examples/*.tfvars
```

---

### 1. Complete Configuration Decisions (REQUIRED NEW STEP)

**Before generating any infrastructure code:**

```bash
# Open and complete the AKS configuration decision guide
code .github/docs/aks-configuration-decisions.md
```

**This guide helps you decide:**
- ✅ Network Plugin (Azure CNI Overlay ⭐ vs Standard)
- ✅ Data Plane (Cilium ⭐ vs IPTables)
- ✅ Network Policy (Cilium ⭐, Azure NPM, Calico)
- ✅ Outbound Type (userDefinedRouting for egress restriction)
- ✅ Security Posture (Standard vs Egress-Restricted)

**Based on official Microsoft documentation and recommendations.**

---

### 2. Choose Your Deployment Scenario
```bash
# For production with compliance requirements:
# Choose Scenario 2B (Platform + Egress Restricted)
cat .github/docs/deployment-scenarios.md
```

### Visual Overview

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Complete AKS Config Decisions ⭐ NEW REQUIRED STEP      │
│    (docs/aks-configuration-decisions.md)                    │
│    → Network plugin, data plane, policy, outbound type     │
│    ↓ Based on Microsoft recommendations                     │
├─────────────────────────────────────────────────────────────┤
│ 2. Choose Deployment Scenario                              │
│    (docs/deployment-scenarios.md)                           │
│    → Scenario 2B for Production                            │
├─────────────────────────────────────────────────────────────┤
│ 3. Generate Hub (prompts/hub-landing-zone.prompt.md)       │
│    → Firewall, Bastion, DNS Zones                          │
│    ↓ Platform Team                                          │
├─────────────────────────────────────────────────────────────┤
│ 4. Generate Spoke (prompts/spoke-aks.prompt.md)            │
│    → Replace [DECISION REQUIRED] placeholders              │
│    → AKS with Cilium, ACR, Key Vault                       │
│    ↓ Application Team                                       │
├─────────────────────────────────────────────────────────────┤
│ 5. Validate (demos/egress-restriction-demo.md)             │
│    → Test workloads, verify firewall rules                 │
└───3. Generate Hub Infrastructure
```bash
# Open in VS Code
code .github/prompts/hub-landing-zone.prompt.md

# Ask Copilot Chat
"Implement this hub landing zone prompt"

# Deploy
cd hub
terraform init
terraform apply
```

### 4. Generate Spoke Infrastructure

**Step 4.1: Complete decisions in the prompt**
```bash
# Open the spoke prompt
code .github/prompts/spoke-aks.prompt.md

# Replace ALL [DECISION REQUIRED] placeholders with your selections from:
# - .github/docs/aks-configuration-decisions.md
# - .github/docs/deployment-scenarios.md

# Or copy from example configuration:
cat .github/examples/prod-egress-restricted.tfvars
```

**Step 4.2: Generate Terraform code**
```bash
# Ask Copilot Chat (after replacing placeholders):
"Implement this spoke AKS prompt with my configuration decisions"

# Copilot will generate Terraform code based on your selections
```

**Step 4.3: Deploy**
```bash
cd spoke-aks
terraform init
terraform apply -var-file=environments/prod.tfvars
```

### 5e_virtual_network       = false
enable_egress_restriction    = true
egress_security_level        = "strict"
# ... other variables
EOF

# Deploy
cd spoke-aks
terraform init
terraform apply -var-file=environments/prod.tfvars
```

### 4. Validate with Demo
```bash
# Follow the demo guide
cat .github/demos/egress-restriction-demo.md

# Run tests to validate egress restrictions
kubectl run egress-test --image=nicolaka/netshoot -it --rm
# ... follow demo steps
```

---

## 📋 File Reference Table

| Category | File | Purpose | Primary Audience | Last Updated |
|----------|------|---------|------------------|-------------|
| **Prompts** | `hub-landing-zone.prompt.md` | Hub infrastructure specification | GitHub Copilot | 2024-01 |
| | `spoke-aks.prompt.md` | Spoke AKS specification with decision placeholders | GitHub Copilot | 2026-01 ⭐ |
| **Docs** | `deployment-scenarios.md` | Decision guide for deployment models | Humans (before deployment) | 2024-01 |
| | `aks-configuration-decisions.md` ⭐ **NEW** | AKS network config guide (plugin, dataplane, policy, egress) | Humans (REQUIRED before AKS deployment) | 2026-01 |
| **Examples** | `dev-standard.tfvars` ⭐ **NEW** | Dev environment config with Azure CNI Overlay + Cilium | Reference | 2026-01 |
| | `prod-egress-restricted.tfvars` ⭐ **NEW** | Production config with egress restriction (Scenario 2B) | Reference | 2026-01 |
| | `prod-standard-cni.tfvars` ⭐ **NEW** | Production with standard CNI (direct pod IPs) | Reference | 2026-01 |
| **Demos** | `egress-restriction-demo.md` | Validation & testing guide | Humans (after deployment) | 2024-01 |
| **Instructions** | `INSTRUCTION_FILES.md` ⭐ **NEW** | Complete reference for all 6 instruction files | Developers | 2026-01 |
| | `azure-verified-modules-terraform.instructions.md` | AVM standards (v0.13+) | Copilot (auto-applied) | 2024-01 |
| | `generate-modern-terraform-code-for-azure.instructions.md` | Modern Terraform code guidelines | Copilot (auto-applied) | 2024-01 |
| | `github-actions-ci-cd-best-practices.instructions.md` | GitHub Actions best practices | Copilot (auto-applied) | 2024-01 |
| | `github-actions-terraform-oidc.instructions.md` ⭐ **NEW** | GitHub Actions Terraform OIDC deployments | Copilot (auto-applied) | 2026-01 |
| | `azure-devops-pipelines.instructions.md` | Azure DevOps pipeline best practices | Copilot (auto-applied) | 2024-01 |
| | `ado-terraform-oidc.instructions.md` | ADO Terraform OIDC deployments | Copilot (auto-applied) | 2024-01 |

- Kubernetes: `>= 1.29` (LTS recommended for Cilium compatibility)
**Version Requirements:**
- Terraform: `>= 1.5.0`
- AVM Network Module: `>= 0.13.0`
- AVM AKS Module: Check prompt files for latest version requirements

---

## 💡 Tips

1. **Reference files in Copilot Chat:**
   - Use `@` to reference files: `@docs/deployment-scenarios.md which scenario should I use for production?`
   - Use `@` with prompts: `@prompts/spoke-aks.prompt.md implement this with egress restriction`

2. **Keep documentation updated:**
   - Update prompts when architecture changes
   - Update scenarios when adding new deployment models
   - Update demos when adding new validation tests

3. **Version control:**
   - All files in `.github/` are version controlled
   - Changes to prompts should be reviewed like code
   - Instructions affect all Terraform code generation

---

## � Troubleshooting
### Decision Placeholders Not Replaced

**Problem:** Tried to generate code but still have `[DECISION REQUIRED]` placeholders in prompt.

**Solution:**
```bash
# Step 1: Complete the decision guide first
code .github/docs/aks-configuration-decisions.md

# Step 2: Review example configurations for guidance
cat .github/examples/prod-egress-restricted.tfvars

# Step 3: Replace ALL placeholders in spoke-aks.prompt.md
# Look for: [DECISION REQUIRED: ...]

# Step 4: Verify all placeholders are replaced
grep "DECISION REQUIRED" .github/prompts/spoke-aks.prompt.md
# Should return no results
```

### Unsure Which Network Plugin to Choose

**Problem:** Don't understand difference between Azure CNI Overlay and Standard.

**Solution:**
```bash
# Read the comprehensive decision guide
code .github/docs/aks-configuration-decisions.md

# Microsoft recommends Azure CNI Overlay for most scenarios:
# - IP conservation (10x more pods per node)
# - Simpler management
# - Better scalability (5,000 nodes vs 400)

# Use Standard CNI only if:
# - Pods MUST have direct VNet IP addresses
# - Existing tools require pod IPs to be routable from VNet
```
### Copilot Not Following Instructions

**Problem:** Generated code doesn't follow AVM standards from instruction files.

**Solution:**
```bash
# Explicitly reference the instruction in your prompt:
"Generate Terraform code following @instructions/azure-verified-modules-terraform.instructions.md"

# Or verify after generation:
"Review this code against @instructions/azure-verified-modules-terraform.instructions.md"
```

### Scenario Selection Confusion

**Problem:** Unsure which scenario to use.

**Solution:**
```bash
# Ask Copilot with context:
"Based on @docs/deployment-scenarios.md, which scenario should I use for a production AKS cluster in a regulated industry where the platform team manages networking?"

# Answer: Scenario 2B (Platform-Provided Networking with Egress Restriction)
```

### Egress Restriction Not Working

**Problem:** After deploying Scenario 2B, pods still have direct internet access.

**Solution:**
```bash
# Follow the validation guide:
cat .github/demos/egress-restriction-demo.md

# Key checks:
# 1. Verify route table has 0.0.0.0/0 → Firewall
az network route-table route list --resource-group rg-spoke-aks-prod --route-table-name rt-aks

# 2. Check AKS outbound type
az aks show --resource-group rg-spoke-aks-prod --name aks-prod --query "networkProfile.outboundType"
# Should return: "userDefinedRouting"

# 3. Test from pod (should fail without firewall allow rule)
kubectl run egress-test --image=nicolaka/netshoot -it --rm -- curl -I https://www.google.com
```

---

## �🔗 Related Files

- **Root README**: `/README.md` - Project overview and getting started
- **Terraform Configurations**: Generated in `/hub/` and `/spoke-aks/` directories
- **Environment tfvars**: Create in `/hub/environments/` and `/spoke-aks/environments/`

---

## 📞 Support

For questions or issues:
1. Check `deployment-scenarios.md` for configuration guidance
2. Review `egress-restriction-demo.md` for testing procedures
3. Ensure prompts are up to date with latest AVM module versions
