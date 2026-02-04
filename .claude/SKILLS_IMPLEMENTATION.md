# GitHub Copilot Agent Skills Implementation

This document describes the Agent Skills implementation for the AKS Landing Zone template repository.

## ✅ Implementation Complete

All skills have been configured according to [GitHub's Agent Skills specification](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills).

## 📁 Skills Directory Structure

```
.claude/skills/
├── README.md
├── create-infrastructure-pr/
│   └── SKILL.md
├── customize-aks-prompts/
│   └── SKILL.md
├── generate-ado-terraform-pipeline/
│   └── SKILL.md
├── generate-aks-spoke/
│   └── SKILL.md
├── parse-customer-requirements/
│   └── SKILL.md
├── terraform/
│   └── generate-hub-infrastructure/
│       └── SKILL.md
└── validate-terraform/
    └── SKILL.md
```

## 🎯 Available Skills

### 1. **generate-hub-infrastructure**
- **Location**: `.claude/skills/terraform/generate-hub-infrastructure/`
- **Trigger**: "Generate hub infrastructure", "Create hub landing zone"
- **Purpose**: Generates Azure hub network infrastructure with Firewall and Bastion
- **Output**: `/infra/terraform/hub/` (flat structure with AVM modules)
- **Input**: `.github/configs/customer-config.json` from parse-customer-requirements
- **References**: `.github/prompts/hub-landing-zone.prompt.md`

### 2. **generate-aks-spoke**
- **Trigger**: "Generate AKS spoke", "Create AKS infrastructure"
- **Purpose**: Generates AKS spoke infrastructure with cluster and networking
- **References**: `.github/prompts/spoke-aks.prompt.md`, `.github/docs/aks-configuration-decisions.md`

### 3. **validate-terraform**
- **Trigger**: "Validate Terraform", "Run validation checks"
- **Purpose**: Validates Terraform code against best practices
- **Executes**: `terraform fmt`, `terraform validate`, `tfsec`, etc.

### 4. **create-infrastructure-pr**
- **Trigger**: "Create PR", "Open pull request"
- **Purpose**: Creates properly formatted PRs with Terraform plan output
- **Follows**: `.github/copilot-instructions.md` workflow

### 5. **customize-aks-prompts**
- **Trigger**: "Help customize prompts", "Configure AKS settings"
- **Purpose**: Guides users through configuration decision process
- **References**: `.github/docs/aks-configuration-decisions.md`

## 📋 SKILL.md Format

Each skill follows the required format:

```markdown
---
name: skill-name-in-lowercase
description: Clear description of what the skill does and when to use it
license: MIT
---

# Skill Title

## Purpose
...

## When to Use This Skill
...

## Instructions
...
```

## 🔄 How Skills Work

1. **User prompts GitHub Copilot** with a request (e.g., "Generate hub infrastructure")
2. **Copilot matches the request** to a skill based on the description in YAML frontmatter
3. **Copilot loads the SKILL.md** into its context
4. **Copilot follows the instructions**, referencing:
   - Prompts in `.github/prompts/`
   - Instructions in `.github/instructions/`
   - Documentation in `.github/docs/`
5. **Copilot generates code** following AVM standards and best practices

## 🏗️ Architecture Integration

```
┌─────────────────────────────────────────────────────────┐
│  .github/instructions/                                  │
│  Standards & Rules                                      │
│  - azure-verified-modules-terraform.instructions.md    │
│  - terraform-azure.instructions.md                      │
└─────────────────────────────────────────────────────────┘
                           ↑
                           │ Enforced by
                           │
┌─────────────────────────────────────────────────────────┐
│  .claude/skills/                                        │
│  Automation & Execution                                 │
│  - Skills with SKILL.md files                          │
└─────────────────────────────────────────────────────────┘
                           ↑
                           │ Reads
                           │
┌─────────────────────────────────────────────────────────┐
│  .github/prompts/                                       │
│  Infrastructure Specifications                          │
│  - hub-landing-zone.prompt.md                          │
│  - spoke-aks.prompt.md (user customizes)              │
└─────────────────────────────────────────────────────────┘
```

## ✨ Benefits

1. **Consistent Code Generation**: Skills ensure all generated code follows AVM standards
2. **Reduced Manual Work**: Automates validation, PR creation, and workflow enforcement
3. **Better Quality**: Enforces pre-commit checks and validation before commits
4. **Guided Customization**: Helps users make informed configuration decisions
5. **Repository Portability**: Skills travel with the repository when forked/cloned

## 🚀 Using Skills

### Example 1: Generate Hub Infrastructure
```
User: "Generate hub infrastructure"
↓
Copilot: Detects generate-hub-infrastructure skill
↓
Copilot: Reads .github/prompts/hub-landing-zone.prompt.md
↓
Copilot: Applies .github/instructions/azure-verified-modules-terraform.instructions.md
↓
Copilot: Generates hub/ directory with Terraform files
↓
Copilot: Runs validation (fmt, validate, AVM checks)
↓
Result: Production-ready hub infrastructure code
```

### Example 2: Validate Before PR
```
User: "Validate my Terraform code"
↓
Copilot: Detects validate-terraform skill
↓
Copilot: Runs terraform fmt -check
↓
Copilot: Runs terraform validate
↓
Copilot: Runs tfsec security scan
↓
Copilot: Reports results and suggests fixes if needed
```

## 🔍 Skills vs Custom Instructions

| Feature | Custom Instructions | Agent Skills |
|---------|-------------------|--------------|
| **Purpose** | General coding standards | Specific task automation |
| **Scope** | Applied to almost every task | Loaded when relevant |
| **Format** | Simple instructions | Structured SKILL.md with frontmatter |
| **Complexity** | Simple rules | Detailed multi-step workflows |
| **Example** | "Use AVM modules" | "How to generate hub infrastructure" |

**Both are used together**: Custom instructions define standards, skills automate execution.

## 📦 Template Repository Behavior

When users fork or use this template:

1. **Skills are inherited** automatically in `.claude/skills/`
2. **Users customize prompts** in `.github/prompts/` for their requirements
3. **Skills remain unchanged** - they reference the customized prompts
4. **Consistent automation** across all template instances

## 🛠️ Compatibility

- ✅ **GitHub Copilot Agent**
- ✅ **GitHub Copilot CLI**
- ✅ **VS Code Agent Mode** (Insiders and stable)
- ✅ **Works across repositories** (personal skills in `~/.copilot/skills/`)

## 📚 References

- [GitHub Agent Skills Documentation](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills)
- [Agent Skills Open Standard](https://github.com/agentskills/agentskills)
- [Anthropic Skills Repository](https://github.com/anthropics/skills)
- [Awesome Copilot Collection](https://github.com/github/awesome-copilot)

## 🎉 Next Steps

The skills are ready to use! Try:

1. "Help me customize the AKS prompts"
2. "Generate hub infrastructure"
3. "Generate AKS spoke infrastructure"
4. "Validate my Terraform code"
5. "Create a pull request"

GitHub Copilot will automatically detect and use the appropriate skill based on your request.
