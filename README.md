# AKS Landing Zone - GitHub Copilot Prompt Template 🚀

[![Template Repository](https://img.shields.io/badge/Repository-Template-blue?style=flat-square)](https://github.com/ckellywilson/aks-lz-ghcp)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)
[![Microsoft Docs](https://img.shields.io/badge/Docs-Microsoft-0078D4?style=flat-square)](https://learn.microsoft.com/azure/aks/)

**⚠️ This is a MINIMAL TEMPLATE repository with basic GitHub Copilot configuration.**

> **Note:** This template has been simplified to provide a minimal starting point. Previous versions contained extensive prompts, documentation, and examples—these are available in the git history if needed. This version focuses on a clean foundation for your infrastructure projects.

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

**⚠️ IMPORTANT:** The template repository ignores `.tf` files for cleanliness. Your infrastructure repository should track `.tf` files.

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
- **Template repo** (this one): Ignores `*.tf` files
- **Your infrastructure repo**: Tracks `*.tf` files (your actual infrastructure code)
- **Both repos**: Ignore state files, secrets, and temporary files

See [.gitignore.template](.gitignore.template) for details.

### Step 3: Build Your Infrastructure

Use GitHub Copilot to develop your Azure infrastructure:

```bash
# Use GitHub Copilot Chat to assist with:
# - Terraform code development
# - Azure resource configuration
# - Best practice implementation
# - Documentation generation
```

GitHub Copilot will use the minimal configuration in `.github/copilot-instructions.md` to assist with your infrastructure development.

### Step 4: Validate & Review

```bash
# Run Terraform validation
terraform fmt -recursive
terraform validate

# Create feature branch and commit
git checkout -b feature/infrastructure-changes
git add .
git commit -m "feat: add infrastructure code"

# Create pull request and request Copilot review
gh pr create --fill
```

### Step 5: Deploy

```bash
# Deploy your infrastructure
terraform init
terraform plan
terraform apply
```

---

## 📦 What This Template Contains

| File/Directory | Purpose |
|----------------|---------|
| `.github/copilot-instructions.md` | Minimal GitHub Copilot configuration |
| `.github/dependabot.yml` | Dependency update automation |
| `docs/` | Project documentation |
| `infra/` | Infrastructure code |
| `scripts/` | Automation scripts |

> **Note:** Previous versions contained extensive prompts, examples, and documentation in `.github/prompts/`, `.github/docs/`, `.github/examples/`, `.github/instructions/`, `.azdo/`, and `.claude/` directories. These have been removed for simplicity. The git history contains these files if you need reference materials.

---

## ✅ What You'll Generate

After using this template, you will create your own infrastructure code:

- Terraform configurations for your Azure resources
- Environment-specific variable files
- Deployment scripts and automation
- Documentation for your infrastructure

**These files will be created in YOUR repository, not this template.**

---

## 🏗️ AKS Best Practices

When building AKS infrastructure, consider these Microsoft-recommended practices:

### Network Configuration

**Microsoft Recommended Production Configuration:**

```hcl
network_plugin              = "azure"
network_plugin_mode         = "overlay"       # Azure CNI Overlay
network_dataplane           = "cilium"        # eBPF performance
network_policy              = "cilium"        # Built-in L3-L7 policies
outbound_type               = "userDefinedRouting"  # Egress restriction
```

**Why this configuration?**
- ✅ IP efficient (10x more pods per node)
- ✅ High performance (eBPF/Cilium)
- ✅ Advanced security (L7 policies, FQDN filtering)
- ✅ Egress restriction ready
- ✅ Scalable (5,000 nodes)

### Security Best Practices

- Use private AKS clusters for production
- Enable Microsoft Defender for Containers
- Implement network policies
- Use Azure Key Vault for secrets
- Enable audit logging
- Regularly update Kubernetes versions

### Architecture Patterns

This template supports **hub-and-spoke network topology** following the [Azure Well-Architected Framework](https://learn.microsoft.com/azure/architecture/framework/) and [AKS Baseline Architecture](https://learn.microsoft.com/azure/architecture/reference-architectures/containers/aks/baseline-aks).

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

## 🤝 Contributing

Contributions to improve this template are welcome!

**✅ DO submit PRs with:**
- Template improvements
- Documentation updates
- Bug fixes
- General enhancements

**❌ Do NOT submit PRs with:**
- Your generated infrastructure code
- Environment-specific configurations
- Company-specific details
- Secrets or credentials

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

---

## 📄 License

This template is licensed under the MIT License. See [LICENSE](LICENSE) for details.

The infrastructure code you generate using this template belongs to you.

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

1. **Start simple** - Begin with basic infrastructure and iterate
2. **Use GitHub Copilot** - Let it assist with Terraform code generation
3. **Follow Azure best practices** - Reference official Microsoft documentation
4. **Review before deploying** - Always validate generated code
5. **Keep learning** - Azure and AKS evolve rapidly

---

## 🆘 Support

- **Template Issues**: Open an issue in this repository
- **Azure Support**: [Azure Support Plans](https://azure.microsoft.com/support/options/)
- **AKS Questions**: [Microsoft Q&A](https://learn.microsoft.com/answers/topics/azure-kubernetes-service.html)

---

**Ready to get started? Click "Use this template" above! 🚀**
