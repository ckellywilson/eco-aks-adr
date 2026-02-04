# GitHub Agent Skills - Visual Workflow

## 🔄 Complete Infrastructure Development Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                     START: Fork Template Repository                  │
└─────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────┐
│  STEP 1: Configuration Planning                                      │
│  User: "Help me customize the prompts"                               │
│  Skill: customize-aks-prompts                                        │
│                                                                       │
│  Actions:                                                             │
│  - Guide through network plugin decisions                            │
│  - Explain data plane options (Cilium vs Azure)                      │
│  - Choose security posture (standard vs egress-restricted)           │
│  - Select deployment model (Model A vs B)                            │
│  - Complete .github/docs/aks-configuration-decisions.md              │
│  - Update .github/prompts/spoke-aks.prompt.md                        │
│                                                                       │
│  Output: ✅ Configuration decisions documented and ready             │
└─────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────┐
│  STEP 2: Generate Hub Infrastructure                                 │
│  User: "Generate hub infrastructure"                                 │
│  Skill: generate-hub-infrastructure                                  │
│                                                                       │
│  Actions:                                                             │
│  - Read .github/prompts/hub-landing-zone.prompt.md                   │
│  - Apply .github/instructions/azure-verified-modules-terraform.md    │
│  - Generate hub/ directory with Terraform files                      │
│  - Create VNet, Firewall, Bastion, DNS zones, Log Analytics          │
│  - Pin module versions, enable telemetry                             │
│  - Run terraform fmt, validate                                       │
│  - Create feature branch                                             │
│                                                                       │
│  Output: hub/ directory with production-ready Terraform code         │
└─────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────┐
│  STEP 3: Validate Hub Code                                           │
│  User: "Validate my Terraform code"                                  │
│  Skill: validate-terraform                                           │
│                                                                       │
│  Actions:                                                             │
│  - terraform fmt -check                                              │
│  - terraform validate                                                │
│  - tfsec security scan                                               │
│  - Optional: checkov for additional security checks                  │
│  - Generate validation report                                        │
│                                                                       │
│  Output: ✅ All validation checks passed, ready for PR               │
└─────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────┐
│  STEP 4: Create Hub Pull Request                                     │
│  User: "Create infrastructure PR"                                    │
│  Skill: create-infrastructure-pr                                     │
│                                                                       │
│  Actions:                                                             │
│  - Generate terraform plan output                                    │
│  - Create PR with conventional commits format                        │
│  - Include validation checklist                                      │
│  - Include review checklist                                          │
│  - Auto-request Copilot review                                       │
│                                                                       │
│  Output: PR created with @github-copilot review requested            │
└─────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────┐
│  MANUAL STEP: Review and Deploy Hub                                  │
│  - Copilot reviews PR automatically                                  │
│  - Human reviewers approve                                           │
│  - Merge PR                                                          │
│  - Deploy: cd hub && terraform apply                                 │
│                                                                       │
│  Output: Hub infrastructure deployed in Azure                        │
└─────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────┐
│  STEP 5: Generate AKS Spoke Infrastructure                           │
│  User: "Generate AKS spoke infrastructure"                           │
│  Skill: generate-aks-spoke                                           │
│                                                                       │
│  Actions:                                                             │
│  - Read .github/prompts/spoke-aks.prompt.md (with user's config)     │
│  - Apply .github/instructions/*.instructions.md                      │
│  - Generate spoke-aks/ directory with Terraform files                │
│  - Implement deployment model (Model A or B)                         │
│  - Apply security posture (standard or egress-restricted)            │
│  - Create VNet, subnets, NSGs, routing, AKS cluster                  │
│  - Generate 3 tfvars: dev, prod-standard, prod-egress-restricted     │
│  - Run terraform fmt, validate                                       │
│  - Create feature branch                                             │
│                                                                       │
│  Output: spoke-aks/ directory with AKS infrastructure code           │
└─────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────┐
│  STEP 6: Validate Spoke Code                                         │
│  User: "Validate my Terraform code"                                  │
│  Skill: validate-terraform                                           │
│  (Same validation process as Step 3)                                 │
└─────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────┐
│  STEP 7: Create Spoke Pull Request                                   │
│  User: "Create infrastructure PR"                                    │
│  Skill: create-infrastructure-pr                                     │
│  (Same PR creation process as Step 4)                                │
└─────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────┐
│  MANUAL STEP: Review and Deploy Spoke                                │
│  - Copilot reviews PR                                                │
│  - Human reviewers approve                                           │
│  - Merge PR                                                          │
│  - Deploy: cd spoke-aks && terraform apply                           │
│                                                                       │
│  Output: AKS Landing Zone complete and operational! 🎉               │
└─────────────────────────────────────────────────────────────────────┘
```

## 🎨 Skill Interaction Diagram

```text
┌─────────────────────────────────────────────────────────────────────┐
│                        Repository Structure                          │
│                                                                       │
│  .github/                                                            │
│  ├── instructions/          ← Standards (AVM, Terraform)             │
│  │   ├── azure-verified-modules-terraform.instructions.md            │
│  │   └── terraform-azure.instructions.md                            │
│  │                                                                    │
│  ├── prompts/              ← Specifications (user customizes)        │
│  │   ├── hub-landing-zone.prompt.md                                 │
│  │   └── spoke-aks.prompt.md   ← User fills [DECISION REQUIRED]     │
│  │                                                                    │
│  ├── docs/                 ← Decision guides                         │
│  │   ├── aks-configuration-decisions.md                             │
│  │   └── deployment-scenarios.md                                    │
│  │                                                                    │
│  └── examples/             ← Reference configs                       │
│      ├── dev-standard.tfvars                                         │
│      └── prod-egress-restricted.tfvars                               │
│                                                                       │
│  .claude/skills/           ← Automation (inherited from template)    │
│  ├── customize-aks-prompts/                                          │
│  ├── generate-hub-infrastructure/                                    │
│  ├── generate-aks-spoke/                                             │
│  ├── validate-terraform/                                             │
│  └── create-infrastructure-pr/                                       │
└─────────────────────────────────────────────────────────────────────┘
                                    ↓
                    ┌───────────────────────────┐
                    │  GitHub Copilot Agent     │
                    │  (Automatically detects   │
                    │   and loads skills)       │
                    └───────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────┐
│                         Skill Execution                              │
│                                                                       │
│  1. User provides natural language prompt                            │
│  2. Copilot matches to skill trigger phrase                          │
│  3. Skill reads:                                                     │
│     - Prompts (specifications)                                       │
│     - Instructions (standards)                                       │
│     - Docs (guidance)                                                │
│     - Examples (reference)                                           │
│  4. Skill generates or validates code                                │
│  5. Skill outputs results to user                                    │
└─────────────────────────────────────────────────────────────────────┘
```

## 🔀 Decision Flow: Network Configuration

```
"Help me customize the prompts"
          ↓
┌─────────────────────┐
│ What's your use     │
│ case?               │
└─────────────────────┘
     ↓           ↓
Production    Dev/Test
     ↓           ↓
┌─────────────────────┐
│ Azure CNI Overlay   │
│ + Cilium            │  ← Microsoft Recommended
│ + Egress Restricted │
└─────────────────────┘
          ↓
┌─────────────────────┐
│ Deployment Model?   │
└─────────────────────┘
     ↓           ↓
Model A      Model B
(App Team)  (Platform)
     ↓           ↓
┌─────────────────────┐
│ Update prompts with │
│ your configuration  │
└─────────────────────┘
          ↓
┌─────────────────────┐
│ Ready to generate   │
│ infrastructure!     │
└─────────────────────┘
```

## 🛠️ Validation Flow

```
"Validate my Terraform code"
          ↓
┌─────────────────────┐
│ terraform fmt       │
│ (Format check)      │
└─────────────────────┘
          ↓ Pass
┌─────────────────────┐
│ terraform validate  │
│ (Syntax check)      │
└─────────────────────┘
          ↓ Pass
┌─────────────────────┐
│ tfsec               │
│ (Security scan)     │  ← RECOMMENDED
└─────────────────────┘
          ↓ Pass
┌─────────────────────┐
│ checkov             │
│ (Additional scans)  │  ← Optional
└─────────────────────┘
          ↓ Pass
┌─────────────────────┐
│ ✅ Validation       │
│    Complete!        │
│ Ready for PR        │
└─────────────────────┘
```

## 📝 PR Creation Flow

```
"Create infrastructure PR"
          ↓
┌─────────────────────┐
│ Pre-flight checks   │
│ - On feature branch?│
│ - Changes committed?│
│ - Branch pushed?    │
└─────────────────────┘
          ↓ Pass
┌─────────────────────┐
│ Gather context      │
│ - Changed files     │
│ - Commit history    │
│ - Detect scope      │
└─────────────────────┘
          ↓
┌─────────────────────┐
│ Generate terraform  │
│ plan output         │
└─────────────────────┘
          ↓
┌─────────────────────┐
│ Create PR with:     │
│ - Conventional title│
│ - Full description  │
│ - Plan output       │
│ - Checklists        │
└─────────────────────┘
          ↓
┌─────────────────────┐
│ Auto-request        │
│ @github-copilot     │
│ review              │
└─────────────────────┘
          ↓
┌─────────────────────┐
│ ✅ PR Created!      │
│ Awaiting Copilot    │
│ review...           │
└─────────────────────┘
```

## 🎯 Quick Command Reference

```
┌──────────────────────────────────────────────────────────┐
│ Common Tasks                                             │
├──────────────────────────────────────────────────────────┤
│                                                          │
│ Configure AKS:                                           │
│   "Help me customize the prompts"                        │
│                                                          │
│ Generate Hub:                                            │
│   "Generate hub infrastructure"                          │
│                                                          │
│ Generate Spoke:                                          │
│   "Generate AKS spoke infrastructure"                    │
│                                                          │
│ Validate:                                                │
│   "Validate my Terraform code"                           │
│                                                          │
│ Create PR:                                               │
│   "Create infrastructure PR"                             │
│                                                          │
│ Get Help:                                                │
│   "How do I configure [network plugin/egress/etc]?"      │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

## 📊 Success Metrics

```
Before Skills                 After Skills
─────────────────────────────────────────────────
⏱️  Days to generate code     →  Minutes
❌ Multiple validation runs   →  One-shot validation
📝 Manual PR formatting       →  Auto-generated PRs
🤔 Configuration guesswork    →  Guided decisions
🔄 Inconsistent patterns      →  Standardized code
⚠️  Review iterations: 3-5    →  Review iterations: 1-2
```

## 🎓 Learning Curve

```
Skill Usage Over Time:

Beginner → Intermediate → Advanced
   ↓            ↓            ↓
Heavy      Moderate      Light
reliance    reliance    reliance
on skills  on skills   on skills
   ↓            ↓            ↓
Guided    Selective   Direct
workflows assistance  specification
```

Skills provide **training wheels** that users can eventually remove as they gain expertise.

---

**For more details, see:**
- `.claude/README.md` - Quick reference
- `.claude/skills/README.md` - Complete documentation
- `.claude/IMPLEMENTATION_SUMMARY.md` - Implementation details
