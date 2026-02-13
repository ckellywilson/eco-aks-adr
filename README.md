# AKS Landing Zone - GitHub Copilot Prompt Template 🚀

[![Template Repository](https://img.shields.io/badge/Repository-Template-blue?style=flat-square)](https://github.com/ckellywilson/aks-lz-ghcp)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)
[![Microsoft Docs](https://img.shields.io/badge/Docs-Microsoft-0078D4?style=flat-square)](https://learn.microsoft.com/azure/aks/)

**⚠️ This is a TEMPLATE repository containing skills and instructions for AI-driven infrastructure generation. We consume Azure Verified Modules but do not contribute to them.**

This repository provides **GitHub Copilot Agent Skills** that generate enterprise-grade Azure infrastructure Terraform code from flexible JSON configuration. Engineers provide a JSON schema defining their topology (multiple hubs, multiple spokes), and GitHub Copilot generates production-ready infrastructure-as-code that follows Microsoft best practices and consumes Azure Verified Modules (AVM) where available.

---

## 🚀 Quick Start

### Step 1: Use This Template

**Click the green "Use this template" button above** (or [click here](../../generate)) to create your own infrastructure repository.

Name your new repository (e.g., `my-company-aks-infrastructure`)

### Step 2: Clone Your New Repository

```bash
git clone https://github.com/YOUR-USERNAME/my-company-aks-infrastructure.git
cd my-company-aks-infrastructure
```

### Step 2.5: Switch to Infrastructure Repository `.gitignore`

**⚠️ IMPORTANT:** The template repository ignores `.tf` files (so prompts/docs remain clean). Your infrastructure repository should track `.tf` files.

```bash
# Replace template .gitignore with infrastructure version
cp .gitignore.template .gitignore

# Create a docs branch for this change (do not work directly on main)
git checkout -b docs/update-gitignore
git add .gitignore
git commit -m "docs(gitignore): update for infrastructure repository"
git push -u origin docs/update-gitignore
```

**What this does:**
- **Template repo** (this one): Ignores `*.tf` files (keeps prompts/docs clean)
- **Your infrastructure repo**: Tracks `*.tf` files (your actual infrastructure code)
- **Both repos**: Ignore state files, secrets, and temporary files

See [.gitignore.template](.gitignore.template) for details.

### Step 3: Generate Infrastructure

#### Workflow: JSON → Terraform

```bash
# Step 3.1: Create flexible JSON configuration
# Define your topology with metadata, globalConstraints, hubs[], spokes[], aksDesign
# Full JSON schema reference documentation will be added in a follow-up PR

# Step 3.2: Generate Terraform code
# In VS Code, open GitHub Copilot Chat and say:
"Generate Terraform from my JSON"

# Copilot will:
# - Read your JSON configuration
# - Create hub-{name}/ folders for each hub
# - Create spoke-{name}/ folders for each spoke
# - Generate provider aliases for multi-subscription
# - Create hub outputs and spoke consumption patterns

# Step 3.3: Validate generated code
"Validate my Terraform code"

# Step 3.4: Deploy infrastructure
cd infra/terraform/hub && ./deploy.sh dev
cd infra/terraform/spoke-aks-prod && ./deploy.sh dev
```

📖 **Learn more:** [.claude/skills/README.md](.claude/skills/README.md)

---

### JSON Configuration Structure

The flexible JSON schema supports:

**Choose based on what your customer has:**

##### Path B1: Customer Provides Natural Language Requirement (Questionnaire)

**Use this if:** Customer describes needs informally ("private AKS with egress control")

```bash
# STEP 1: Capture customer requirements using questionnaire (5 minutes)
code .github/docs/customer-requirements-quick-reference.md

# Answer 8 essential questions:
# 1. Cluster isolation (Private/Public)?
# 2. Egress control (Restricted/Permissive)?
# 3. Network connectivity (App Gateway/Load Balancer)?
# 4. Pod density (Overlay/Standard)?
# 5. Cilium eBPF (Yes/No)?
# 6. Governance model (Scenario 1-4)?
# 7. Environment (Dev/Staging/Prod)?
# 8. Compliance (None/PCI-DSS/HIPAA/etc)?

# STEP 2: Pass to Agent Skills (Option A)
# The questionnaire will direct you to Agent Skills
# Agent Skills automates: configuration extraction, Hub generation, Spoke generation
```

📖 **Questionnaire Path Resources:**
- [Quick Reference Form](.github/docs/customer-requirements-quick-reference.md) ⭐ - **Start here**

**Time**: ~5 minutes (capture only; Agent Skills automates the rest)

---

##### Path B2: Customer Provides Architecture Decision Record (ADR)

**Use this if:** Customer has formal ADR with design decisions documented

```bash
# STEP 1: Get ADR from customer
# Collect their Architecture Decision Record document
# Expected to include Hub + Spoke infrastructure decisions

# STEP 2: Extract Hub requirements (10 minutes)
code .github/docs/adr-to-hub-extraction-guide.md

# Use comprehensive WAF-aligned extraction checklist:
# - Reliability (Availability, Backup, RTO/RPO)
# - Security (Firewall, Identity, Compliance)
# - Cost Optimization (SKU Strategy, Reservations)
# - Operational Excellence (IaC, GitOps, Observability)
# - Performance Efficiency (Scale, Latency SLA)
# - Hybrid Connectivity (ExpressRoute, DNS)

# STEP 3: Choose your workflow
# Option A: Pass extracted variables to Agent Skills (automated) ⭐ RECOMMENDED
#   Result: Automated Hub + Spoke code generation
# Option C: Use extracted variables in manual workflow (full control)
#   Result: Manual configuration with extracted values
```

📖 **ADR Extraction Path Resources:**
- [ADR Extraction Guide](.github/docs/adr-to-hub-extraction-guide.md) ⭐ - **Start here**
- [Ecolab ADR Example](.github/docs/adr-to-hub-extraction-guide.md#ecolab-adr-example-waf-aligned) - Real example with all 5 WAF pillars
- [WAF-Aligned Checklist](.github/docs/adr-to-hub-extraction-guide.md#hub-extraction-checklist-waf-aligned) - Comprehensive extraction

**Time**: ~10 minutes (extraction only; Agent Skills or manual configuration follows)

---

**Path Comparison:**

| Aspect | Questionnaire (B1) | ADR (B2) |
|--------|-------------------|---------|
| **Customer Input Type** | Natural language | Formal document |
| **Best For** | Quick customer interviews | Enterprise customers |
| **Capture/Extract Time** | 5 minutes | 10 minutes |
| **Detail Level** | 8 key questions | 5 WAF pillars |
| **Example** | "Private, secure AKS" | Full architectural decisions |
| **Next Step** | Pass to Agent Skills (Option A) | Pass to Agent Skills (Option A) or use manually (Option C) |
| **Output** | Automated code generation | Automated code OR manual variables |

**Process Time Overall**: 
- **B1 + Agent Skills**: ~5 min capture + automated generation = fastest path ⚡
- **B2 + Agent Skills**: ~10 min extract + automated generation = comprehensive path ⚡
- **B2 + Manual (Option C)**: ~10 min extract + 5-10 min manual config = full control

---

**After completing B1 or B2 (Option B):** The recommended next step is to pass your outputs to Agent Skills (Option A) for automated code generation. Alternatively, proceed to Option C below (B1 optional, B2 alternative) using the identified configuration type or extracted Hub variables.

---

#### Option C: Manual Workflow (Configuration Decision to Code Generation)

**Use this after capturing customer requirements (Option B) OR to manually configure:**

```bash
# STEP 1: Review your configuration decisions
# These come from Option B (customer input) OR your manual selections
code .github/docs/aks-configuration-decisions.md

# STEP 2: Review deployment scenarios & governance model
code .github/docs/deployment-scenarios.md

# STEP 3: Review or create your terraform.tfvars
# Reference examples for your configuration type:
code .github/examples/prod-egress-restricted.tfvars    # Most production use cases
# OR
code .github/examples/prod-standard-cni.tfvars         # Production without Cilium
# OR
code .github/examples/dev-standard.tfvars              # Development environments

# STEP 4: Generate hub infrastructure
code .github/prompts/hub-landing-zone.prompt.md
# Ask Copilot: "Implement this hub landing zone prompt using prod-egress-restricted.tfvars"

# STEP 5: Generate spoke infrastructure
code .github/prompts/spoke-aks.prompt.md
# Replace any [DECISION REQUIRED] placeholders with your values from STEP 1
# Ask Copilot: "Implement this spoke AKS prompt with my configuration decisions"
```

📖 **Configuration Guides:**
- [AKS Configuration Decisions](.github/docs/aks-configuration-decisions.md) - Detailed options
- [Quick Configuration Reference](.github/docs/aks-configuration-quick-reference.md) - One-page reference

---

---

## 🎯 Complete Workflow Map (Steps 3-5)

**Use this to navigate from Step 3 through Step 5:**

### If You Chose Option A (Agent Skills)

```
START HERE: Option A - Automated
    ↓
📍 You are here (README.md Step 3)
    ↓
Go to: .claude/skills/README.md
    ↓
Follow: "Help me customize the prompts"
    ↓
Skills automate: Hub generation → Spoke generation → Validation
    ↓
RESULT: Ready for Step 4 & 5 (review and deploy)
```

### If You Chose Option B, Path B1 (Customer Questionnaire)

```
START HERE: Option B1 - Customer Questionnaire
    ↓
📍 You are here (README.md Step 3)
    ↓
STEP 3B1-1: Capture customer requirements (5 min)
    Go to: .github/docs/customer-requirements-quick-reference.md
    Answer: 8 questions from the form
    Document: Customer's answers
    ↓
⚡ CHOOSE YOUR PATH:
    ↓
    RECOMMENDED: Agent Skills (Automated)
    ├─ Action: Follow questionnaire's Agent Skills instructions
    ├─ Agent Skills automates: Configuration extraction, Hub generation, Spoke generation
    ├─ Result: Infrastructure code ready for review and deployment
    └─ Time: Automated (no additional steps)
    ↓
    OR: Manual Option C Workflow
    ├─ Use: aks-configuration-decisions.md to configure manually
    ├─ Process: Manual configuration with prompts
    ├─ Result: Infrastructure code via manual workflow
    └─ Time: ~8 minutes additional (3 map + 5 configure)
    ↓
RESULT: Infrastructure code ready for review and deployment
```

### If You Chose Option B, Path B2 (Customer ADR)

```
START HERE: Option B2 - Customer ADR Extraction
    ↓
📍 You are here (README.md Step 3)
    ↓
STEP 3B2-1: Extract Hub requirements from ADR (10 min)
    Go to: .github/docs/adr-to-hub-extraction-guide.md
    Use: WAF-aligned extraction checklist
    Extract: 5 pillars (Reliability, Security, Cost, OpEx, Performance)
    Result: Hub requirements documented
    ↓
STEP 3B2-2: Map ADR to Terraform variables (5 min)
    Go to: Same document (adr-to-hub-extraction-guide.md)
    Reference: Variable mapping section
    Result: Hub Terraform variables extracted from ADR
    ↓
STEP 3B2-3: Review Ecolab example (optional, 5 min)
    Go to: ADR extraction guide - Ecolab example section
    Understand: Full WAF-aligned ADR extraction in practice
    ↓
STEP 3B2-4: Transition to Option C Workflow (below)
    Note: For automated path, see Agent Skills section above instead
    Use: Your extracted Hub variables if proceeding manually
    Continue: With Option C steps
    ↓
RESULT: Ready for Step 4 & 5 (review and deploy)
```

### If You Chose Option C (Manual Configuration)

```
START HERE: Option C - Manual Workflow
    ↓
📍 You are here (README.md Step 3, Option C)
    ↓
STEP 3C-1: Review configuration decisions
    Go to: .github/docs/aks-configuration-decisions.md
    Review: Configuration options for your setup
    Note: If from Option B, use identified configuration
    ↓
STEP 3C-2: Review deployment scenarios
    Go to: .github/docs/deployment-scenarios.md
    Choose: Your governance model (Scenario 1-4)
    Understand: Implications for your deployment
    ↓
STEP 3C-3: Review example configuration
    Go to: .github/examples/
    Choose: tfvars file matching your configuration
    Options:
      - dev-standard.tfvars (development)
      - prod-standard-cni.tfvars (production, standard)
      - prod-egress-restricted.tfvars (production, secure)
    ↓
STEP 3C-4: Generate hub infrastructure
    Go to: .github/prompts/hub-landing-zone.prompt.md
    Copy: Prompt content
    Configure: Your chosen tfvars base file
    Ask Copilot: "Implement this hub landing zone prompt"
    Result: hub/ directory with infrastructure code
    ↓
STEP 3C-5: Generate spoke infrastructure
    Go to: .github/prompts/spoke-aks.prompt.md
    Copy: Prompt content
    Configure: Your chosen tfvars base file + specific settings
    Ask Copilot: "Implement this spoke AKS prompt"
    Result: spoke-aks/ directory with infrastructure code
    ↓
RESULT: Ready for Step 4 & 5 (review and deploy)
```

---

### Step 4: Validate & Review

```bash
# Run Terraform validation
terraform fmt -recursive
terraform validate

# Create feature branch and commit
git checkout -b feature/infrastructure-hub
git add hub/
git commit -m "feat(hub): add landing zone infrastructure"

# Create pull request and request Copilot review
gh pr create --fill
```

### Step 4: Validate & Review

Review the pull request and address any Copilot feedback.

### Step 5: Deploy

```bash
cd hub
terraform init
terraform apply

cd ../spoke-aks
terraform init
terraform apply
```

---

## 📦 What This Template Contains

| Directory | Contents | Purpose |
|-----------|----------|---------|
| `.claude/skills/` | GitHub Agent Skills for automated workflows | Streamline infrastructure generation with AI automation ⭐ |
| `.github/prompts/` | GitHub Copilot prompts for infrastructure generation | Code generation specifications |
| `.github/docs/` | Decision guides and reference documentation | Help you make informed configuration choices |
| `.github/examples/` | Example tfvars configurations | Reference for common scenarios |
| `.github/instructions/` | Auto-applied Copilot coding standards | Ensure generated code follows AVM standards |
| `.github/demos/` | Validation and testing guides | Verify deployed infrastructure |

---

## ✅ What You'll Generate (In Your Repo)

After using this template, **you** will generate:

- `hub/` - Hub landing zone Terraform code (Azure Firewall, Bastion, DNS zones)
- `spoke-aks/` - AKS spoke Terraform code (AKS cluster, ACR, Key Vault, networking)
- `environments/` - Environment-specific tfvars files (dev, prod, etc.)

**These files will be created in YOUR repository, not this template.**

---

## 🔄 How Customer Requirements Map to Infrastructure

This framework shows how customer input translates into infrastructure code via two paths:

```
CUSTOMER INPUT
├─ Path B1: Natural Language (Questionnaire)
│   │
│   ├─ "Private AKS cluster with egress control"
│   ├─ "Production environment, highly available"
│   │
│   ↓ STEP 1: CAPTURE (8 Questions, 5 min)
│   │
│   ├─ Use: customer-requirements-quick-reference.md
│   ├─ Answer 8 essential questions
│   ├─ Output: Customer answers documented
│   │
│   ↓ DECISION: Choose next path
│   │
│   ├─ RECOMMENDED: Agent Skills (automated, ~5 min total)
│   │   └─ Follow Agent Skills workflow above
│   │
│   └─ ALTERNATIVE: Manual Option C workflow below (~13 min total)
│       ↓ STEP 2: MAP (3 min)
│       ├─ Reference: Decision mapping table
│       ├─ Configuration Type: prod-egress-restricted
│       └─ Base tfvars: prod-egress-restricted.tfvars
│
└─ Path B2: Formal ADR Document
    │
    ├─ Architecture Decision Record (ADR)
    ├─ Hub + Spoke architecture documented
    ├─ 5 WAF pillars defined
    │
    ↓ STEP 1: EXTRACT (10 min)
    │
    ├─ Use: adr-to-hub-extraction-guide.md
    ├─ WAF-aligned extraction checklist
    ├─ Output: Hub requirements per pillar
    │
    ↓ STEP 2: MAP (5 min)
    │
    ├─ Reference: Variable mapping section
    ├─ Map ADR to Terraform variables
    ├─ Output: Hub variables (extracted)
    │
    ↓ DECISION: Choose next path
    │
    ├─ RECOMMENDED: Agent Skills (automated)
    │   └─ Follow Agent Skills workflow above
    │
    └─ ALTERNATIVE: Manual Option C workflow below

    MANUAL PATHS CONVERGE AT OPTION C
              ↓
    STEP 3: CONFIGURE (Option C Workflow)
              ↓
    ├─ Use: aks-configuration-decisions.md
    ├─ Reference: .github/examples/*.tfvars
    ├─ Copy: Configuration values into prompts
              ↓
    STEP 4: GENERATE (5-10 min)
              ↓
    ├─ Use: .github/prompts/hub-landing-zone.prompt.md
    ├─ With: Your configuration (B1) or extracted vars (B2)
    ├─ Generate: Hub infrastructure
              ↓
    STEP 5: VALIDATE & DEPLOY
              ↓
    └─ Infrastructure ready for review
```

> **Note:** The workflow diagram above shows the **manual convergence path only** (both B1 and B2 can proceed to Option C for manual configuration). For the **recommended automated workflow**, B1 and B2 should use Agent Skills (Option A) instead—see the timing comparison below.

**Workflow Timing:**

*Agent Skills Paths (Automated, fastest):*
- B1 + Agent Skills: ~5 minutes (capture only) + automated generation ⚡
- B2 + Agent Skills: ~10 minutes (extraction) + automated generation ⚡

*Manual Paths (Full control):*
- B1 → Option C (Manual): ~13 minutes (5 capture + 3 map + 5 configure)
- B2 → Option C (Manual): ~15 minutes (10 extract + 5 configure)
- Option C only: 5-10 minutes (manual configuration)

**Total Time to Ready-to-Review Code:**
- Agent Skills (fastest): ~5-10 minutes (requirements capture + automated generation) ⚡
- Manual workflows: ~13-15 minutes (requirements capture + manual configuration)

---

## ✅ Key Integration Points

| Component | Purpose | Input Path | Output |
|-----------|---------|------------|--------|
| **Customer Requirements Quick Reference** | Capture customer needs via 8 questions | B1 (Questionnaire) | Automated code generation via Agent Skills |
| **ADR Extraction Guide** | Extract Hub requirements from formal ADR using WAF pillars | B2 (ADR Document) | Hub variables OR automated code via Agent Skills |
| **Configuration Mapping** | Manual reference for custom configurations | C (Manual workflow) | Identified configuration type |
| **AKS Configuration Decisions** | Detailed configuration options reference | C (Manual workflow) | Decision documentation |
| **Example tfvars Files** | Base configurations for common scenarios | C (Manual workflow) | Terraform variables |
| **Copilot Prompts** | Generate infrastructure code | C (Manual workflow) | Code generation |
| **Coding Instructions** | Auto-apply AVM standards and best practices | All | Code generation quality |
| **Agent Skills** | Automate entire workflow | A (Automated) + B paths | Full infrastructure |

**Key Difference:**
- **B1 (Questionnaire)**: Fastest input → Choose Agent Skills (automated, ~5 min total) OR Option C (manual, ~13 min total)
- **B2 (ADR)**: Comprehensive extraction (~10 min) → Choose Agent Skills (automated generation) OR Option C (manual workflow, ~15 min total)
- **Option C**: Maximum control, manual workflow with extracted/reference values
- **Manual paths only**: B1 and B2 manual variants can converge at Option C using identified configuration or extracted variables

---

## 🚀 Common Usage Patterns

### Pattern 1: Customer Provides Requirements (Option B → C)
1. Customer gives natural language requirement (e.g., "private, secure AKS")
2. You use customer-requirements-quick-reference.md to capture input
3. Map to configuration type (e.g., prod-egress-restricted)
4. Use that configuration in Option C manual workflow
5. Copilot generates infrastructure with correct settings

### Pattern 2: Manual Configuration (Option C Only)
1. You manually review aks-configuration-decisions.md
2. Select configuration options
3. Use Option C to generate code with your choices

### Pattern 3: Automated Workflow (Option A)
1. Agent skills guide entire process
2. Can optionally use customer requirements framework as input
3. Skills automate configuration and code generation

---

## 🏗️ Deployment Scenarios

This template supports four deployment scenarios based on your governance model:

| Scenario | Description | Use Case |
|----------|-------------|----------|
| **Scenario 1** | Full Application Team Autonomy | Dev/test environments |
| **Scenario 2** ⭐ | Platform-Provided Networking | **Production (Recommended)** |
| **Scenario 3** | Hybrid Model | Transitioning governance |
| **Scenario 4** | Security-First Model | Maximum compliance |

Each scenario has security variants:
- **Variant A**: Standard Security (permissive egress)
- **Variant B**: Egress-Restricted Security (force tunnel via Azure Firewall) ⭐ **Recommended for Production**

📖 **Read:** [.github/docs/deployment-scenarios.md](.github/docs/deployment-scenarios.md)

---

## 🌐 AKS Network Configuration Options

Based on official Microsoft documentation (January 2026):

### Microsoft Recommended Production Configuration ⭐

```hcl
network_plugin              = "azure"
network_plugin_mode         = "overlay"       # Azure CNI Overlay
network_dataplane           = "cilium"        # eBPF performance
network_policy              = "cilium"        # Built-in L3-L7 policies
outbound_type               = "userDefinedRouting"  # Egress restriction
enable_egress_restriction   = true
```

**Why this configuration?**
- ✅ IP efficient (10x more pods per node)
- ✅ High performance (eBPF/Cilium)
- ✅ Advanced security (L7 policies, FQDN filtering)
- ✅ Egress restriction ready
- ✅ Scalable (5,000 nodes)

### Configuration Options

| Component | Options | Microsoft Recommendation |
|-----------|---------|-------------------------|
| **Network Plugin** | Azure CNI Overlay, Azure CNI Standard | **Azure CNI Overlay** ⭐ |
| **Data Plane** | Cilium (eBPF), IPTables | **Cilium** ⭐ |
| **Network Policy** | Cilium, Azure NPM, Calico | **Cilium** ⭐ |
| **Outbound Type** | userDefinedRouting, loadBalancer, NAT Gateway | **userDefinedRouting** (for egress restriction) ⭐ |

📖 **Complete Guide:** [.github/docs/aks-configuration-decisions.md](.github/docs/aks-configuration-decisions.md)  
📖 **Quick Reference:** [.github/docs/aks-configuration-quick-reference.md](.github/docs/aks-configuration-quick-reference.md)

---

## 📚 Documentation Structure

```
.claude/
├── skills/                     # GitHub Agent Skills (automated workflows) ⭐
│   ├── README.md              # Complete skills documentation
│   ├── customize-aks-prompts/
│   ├── generate-hub-infrastructure/
│   ├── generate-aks-spoke/
│   ├── validate-terraform/
│   └── create-infrastructure-pr/
└── README.md                   # Quick skills reference

.github/
├── prompts/                    # GitHub Copilot code generation prompts
│   ├── hub-landing-zone.prompt.md
│   └── spoke-aks.prompt.md
├── docs/                       # Customer input, decision guides, and reference
│   ├── customer-requirements-quick-reference.md    # 8-question form (B1 Path) ⭐
│   ├── adr-to-hub-extraction-guide.md              # WAF-aligned ADR extraction (B2 Path) ⭐
│   ├── aks-configuration-decisions.md              # Configuration options reference
│   ├── aks-configuration-quick-reference.md        # Quick config reference
│   └── deployment-scenarios.md                     # Governance models
├── examples/                   # Reference configurations (from customer input mapping)
│   ├── dev-standard.tfvars                         # Development
│   ├── prod-egress-restricted.tfvars               # Production (recommended)
│   └── prod-standard-cni.tfvars                    # Production alternative
├── instructions/               # Auto-applied Copilot instructions
│   ├── azure-verified-modules-terraform.instructions.md
│   └── terraform-azure.instructions.md
└── demos/                      # Validation guides (use AFTER deployment)
    └── egress-restriction-demo.md
```

### Documentation Workflow

> **Note:** This diagram shows the **manual workflow convergence only** (B1/B2 → Option C). For the **recommended workflow**, B1 and B2 should use **Agent Skills (Option A)** for automated generation instead.

```
OPTION A: AUTOMATED SKILLS ⭐ RECOMMENDED
├── .claude/skills/README.md
└── Can be used alone OR after B1/B2 requirement capture

OPTION B: CUSTOMER INPUT (Choose your entry point)
├── Path B1: Questionnaire → Then Agent Skills (Option A) ⭐
│   ├── customer-requirements-quick-reference.md (8 questions)
│   └── Alternative: Can proceed to Option C for manual workflow
│
└── Path B2: ADR Extraction → Then Agent Skills (Option A) ⭐ OR Option C
    ├── adr-to-hub-extraction-guide.md (5 WAF pillars)
    └── Alternative: Can proceed to Option C for manual workflow
    
OPTION C: MANUAL WORKFLOW (Manual alternative for B1 & B2)
├── aks-configuration-decisions.md
├── .github/examples/*.tfvars
├── .github/prompts/hub-landing-zone.prompt.md
├── .github/prompts/spoke-aks.prompt.md
└── Auto-applied: .github/instructions/*.instructions.md

RESULT: Infrastructure Code (hub/ + spoke-aks/)
```

---

## 🔄 Keeping Prompts Updated (Optional)

This template is regularly updated with the latest Azure best practices and AKS features. To sync updates:

### Option 1: Manual Sync (Recommended)

```bash
# Add this template as a remote
git remote add template https://github.com/YOUR-ORG/aks-lz-ghcp.git

# Fetch latest prompts
git fetch template

# Merge only the .github directory
git checkout template/main -- .github/prompts
git checkout template/main -- .github/docs
git checkout template/main -- .github/instructions
git checkout template/main -- .github/examples

# Commit updates
git commit -m "chore: sync prompts from template"
```

### Option 2: GitHub Action (Automated)

Enable the included workflow (uncomment in `.github/workflows/sync-prompts.yml`) to automatically check for prompt updates weekly.

---

## 🏗️ Architecture

This template generates a **hub-and-spoke network topology** following the [Azure Well-Architected Framework](https://learn.microsoft.com/azure/architecture/framework/) and [AKS Baseline Architecture](https://learn.microsoft.com/azure/architecture/reference-architectures/containers/aks/baseline-aks).

### Hub Landing Zone
- Azure Firewall (egress control)
- Azure Bastion (secure access)
- Private DNS Zones
- VPN/ExpressRoute Gateway
- Centralized logging

### AKS Spoke Landing Zone
- AKS cluster with flexible networking options
- Azure Container Registry (ACR)
- Azure Key Vault
- Private endpoints
- Network security groups
- User-defined routing (optional egress restriction)

---

## 🛠️ Prerequisites

Before using this template:

1. **Azure Subscription** with appropriate permissions
2. **GitHub Copilot** subscription (Individual, Business, or Enterprise)
3. **VS Code** with GitHub Copilot extension installed
4. **Azure CLI** (`>= 2.50.0`)
5. **Terraform** (`>= 1.5.0`)
6. **Basic knowledge** of:
   - Azure networking concepts
   - Kubernetes fundamentals
   - Terraform basics

---

## 📖 Detailed Workflow

### 1. Complete Configuration Decisions (REQUIRED)

Open and complete **ALL** sections:

```bash
code .github/docs/aks-configuration-decisions.md
```

This guide helps you select:
- ✅ Network Plugin (Azure CNI Overlay vs Standard)
- ✅ Data Plane (Cilium vs IPTables)
- ✅ Network Policy Engine (Cilium, Azure NPM, Calico)
- ✅ Outbound Type (userDefinedRouting, loadBalancer, NAT Gateway)
- ✅ Security Posture (Standard vs Egress-Restricted)

**Do NOT skip this step!** The spoke prompt requires these decisions.

### 2. Review Deployment Scenarios

```bash
code .github/docs/deployment-scenarios.md
```

Choose your deployment model based on organizational governance.

### 3. Review Example Configurations

```bash
# Development environment
cat .github/examples/dev-standard.tfvars

# Production with egress restriction (RECOMMENDED)
cat .github/examples/prod-egress-restricted.tfvars

# Production with standard CNI
cat .github/examples/prod-standard-cni.tfvars
```

### 4. Generate Hub Infrastructure

```bash
code .github/prompts/hub-landing-zone.prompt.md
```

Ask GitHub Copilot: `"Implement this hub landing zone prompt"`

### 5. Generate Spoke Infrastructure

```bash
code .github/prompts/spoke-aks.prompt.md
```

1. Replace **ALL** `[DECISION REQUIRED]` placeholders with your selections
2. Ask GitHub Copilot: `"Implement this spoke AKS prompt with my configuration decisions"`

### 6. Validate Deployment

```bash
code .github/demos/egress-restriction-demo.md
```

Follow the validation guide to test your infrastructure.

---

## 🤝 Contributing

Found an issue with prompts or documentation? Contributions are welcome!

**✅ DO submit PRs with:**
- Prompt improvements
- Documentation updates
- Bug fixes in decision guides
- New example configurations

**❌ Do NOT submit PRs with:**
- Your generated Terraform code
- Your environment-specific configurations
- Your company's infrastructure details

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

---

## 📄 License

This template is licensed under the MIT License. See [LICENSE](LICENSE) for details.

The infrastructure code **you generate** using this template belongs to you and can be licensed as you choose.

---

## 🔗 Resources

### Official Microsoft Documentation
- [Azure Kubernetes Service Documentation](https://learn.microsoft.com/azure/aks/)
- [AKS Baseline Architecture](https://learn.microsoft.com/azure/architecture/reference-architectures/containers/aks/baseline-aks)
- [Azure CNI Powered by Cilium](https://learn.microsoft.com/azure/aks/azure-cni-powered-by-cilium)
- [Azure Verified Modules](https://aka.ms/avm)

### Related Projects
- [AKS Baseline Reference Implementation](https://github.com/mspnp/aks-baseline)
- [Azure Landing Zones](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/)
- [Terraform AzureRM Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

---

## 💡 Tips

1. **Use Agent Skills** ⭐ - Say "Help me customize the prompts" to start the automated workflow
2. **Start with decisions** - Complete `.github/docs/aks-configuration-decisions.md` before generating code
3. **Use examples** - Reference `.github/examples/*.tfvars` for proven configurations
4. **Validate early** - Use `.github/demos/egress-restriction-demo.md` to verify deployments
5. **Keep prompts updated** - Sync from template regularly for latest best practices
6. **Ask Copilot** - Use `@` to reference files in Copilot Chat: `@docs/deployment-scenarios.md which scenario for production?`
7. **Quick commands** - See [.claude/README.md](.claude/README.md) for all available skill commands

---

## 🆘 Support

- **Documentation Issues**: Open an issue in this template repository
- **Azure Support**: [Azure Support Plans](https://azure.microsoft.com/support/options/)
- **AKS Questions**: [Microsoft Q&A](https://learn.microsoft.com/answers/topics/azure-kubernetes-service.html)

---

## ⭐ Version Information

**Template Version:** v1.0.0  
**Last Updated:** January 2026  
**Based on:** 
- Azure Verified Modules (AVM) standards
- Microsoft AKS best practices (January 2026)
- Azure CNI Powered by Cilium (latest)

---

**Ready to get started? Click "Use this template" above! 🚀**
