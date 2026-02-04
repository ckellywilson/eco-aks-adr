# Template Repository Setup Checklist

This checklist helps you finalize the template repository before making it public.

## ✅ Repository Configuration (Do in GitHub Settings)

### Step 1: Enable Template Repository

- [ ] Go to repository **Settings**
- [ ] Scroll to **Template repository** section
- [ ] ✅ Check **"Template repository"**
- [ ] Click **Save**

### Step 2: Update Repository Details

- [ ] **Description**: "AKS Landing Zone - GitHub Copilot Prompt Template 🚀"
- [ ] **Website**: (Optional) Link to documentation
- [ ] **Topics**: Add tags
  - `azure-kubernetes-service`
  - `aks`
  - `github-copilot`
  - `infrastructure-as-code`
  - `terraform`
  - `azure-verified-modules`
  - `landing-zone`
  - `template`

### Step 3: Configure Branch Protection

- [ ] Go to **Settings** → **Branches**
- [ ] Click **Add rule** for `main` branch
- [ ] Enable:
  - ✅ Require pull request reviews before merging
  - ✅ Require status checks to pass
  - ✅ Require conversation resolution before merging
  - ✅ Do not allow bypassing the above settings
- [ ] Click **Create**

### Step 4: Configure Security

- [ ] Go to **Settings** → **Security & analysis**
- [ ] Enable:
  - ✅ Dependency graph
  - ✅ Dependabot alerts
  - ✅ Dependabot security updates
  - ✅ Secret scanning
  - ✅ Private vulnerability reporting

### Step 5: Disable Unnecessary Features

- [ ] Go to **Settings** → **General**
- [ ] Under **Features**, disable:
  - ❌ Wikis (not needed for template)
  - ❌ Projects (not needed)
  - ❌ Allow forking (force template usage instead)

---

## 📝 Update Template Files

### Update Placeholders

- [ ] **README.md**
  - [ ] Replace `YOUR-ORG` with your GitHub organization
  - [ ] Replace `YOUR-USERNAME` with appropriate references
  - [ ] Update template repository URL

- [ ] **CONTRIBUTING.md**
  - [ ] Replace `YOUR-ORG` with your GitHub organization
  - [ ] Update contact information

- [ ] **.github/workflows/sync-prompts.yml**
  - [ ] Update `TEMPLATE_REPO` URL with actual repository URL

- [ ] **.github/TEMPLATE_INSTRUCTIONS.md**
  - [ ] Update template repository URL

- [ ] **LICENSE**
  - [ ] Replace `[Your Organization Name]` with actual organization name

### Review Content

- [ ] Review all `.md` files for accuracy
- [ ] Verify all links work
- [ ] Check code examples are correct
- [ ] Ensure no sensitive information

---

## 🔍 Test Template Locally

### Create Test Repository

```bash
# From a different directory (not in template repo)
cd /tmp

# Simulate "Use this template"
git clone https://github.com/YOUR-ORG/aks-lz-ghcp.git test-aks-lz
cd test-aks-lz

# Remove git history (simulates fresh template usage)
rm -rf .git
git init
git add .
git commit -m "Initial commit from template"
```

### Verify Template Structure

- [ ] `.github/` directory exists
- [ ] All documentation files present
- [ ] Example configurations available
- [ ] Workflows configured
- [ ] `.gitignore` prevents code generation

### Test Decision Guide

- [ ] Open `code .github/docs/aks-configuration-decisions.md`
- [ ] Verify all sections are clear
- [ ] Check that decision checkboxes work
- [ ] Verify links to official Microsoft docs

### Test Prompt

- [ ] Open `.github/prompts/spoke-aks.prompt.md`
- [ ] Verify `[DECISION REQUIRED]` placeholders present
- [ ] Test with GitHub Copilot (if available)
- [ ] Verify Copilot refuses to generate without replacements

---

## 🚀 Initial Release

### Create v1.0.0 Release

- [ ] Go to **Releases**
- [ ] Click **Draft a new release**
- [ ] Create tag: `v1.0.0`
- [ ] Release title: `v1.0.0 - Initial Release`
- [ ] Release notes:

```markdown
# v1.0.0 - Initial Release 🚀

First stable release of the AKS Landing Zone GitHub Copilot Prompt Template.

## 🎯 Features

- Complete AKS Landing Zone prompt templates
- Comprehensive decision guides based on Microsoft best practices (January 2026)
- Support for 4 deployment scenarios with security variants
- Azure CNI Overlay + Cilium (Microsoft recommended configuration)
- Example configurations for dev and production
- Auto-sync workflow for prompt updates

## 📚 Documentation

- AKS configuration decision guide (network plugin, data plane, policies)
- Deployment scenario guide (4 models: team autonomy to platform-provided)
- Quick reference for configuration options
- Egress restriction demo and validation guide

## 🔧 Configuration Options

Based on official Microsoft documentation:
- **Network Plugin**: Azure CNI Overlay (recommended), Azure CNI Standard
- **Data Plane**: Cilium eBPF (recommended), IPTables
- **Network Policy**: Cilium (recommended), Azure NPM, Calico
- **Outbound Type**: userDefinedRouting, loadBalancer, NAT Gateway

## 📦 What's Included

- `.github/prompts/` - Copilot code generation prompts
- `.github/docs/` - Decision guides and references
- `.github/examples/` - Example tfvars configurations
- `.github/instructions/` - Auto-applied coding standards
- `.github/demos/` - Validation guides

## 🚀 Getting Started

1. Click "Use this template" to create your infrastructure repo
2. Complete `.github/docs/aks-configuration-decisions.md`
3. Generate code with GitHub Copilot
4. Deploy to Azure

## 📖 Documentation

See [README.md](README.md) for complete instructions.

## 🙏 Credits

Based on:
- Azure Verified Modules (AVM) standards
- Microsoft AKS best practices
- Azure Well-Architected Framework
```

- [ ] Click **Publish release**

---

## 📢 Announce Template

### Internal Announcement

- [ ] Share with your team/organization
- [ ] Create documentation in internal wiki
- [ ] Schedule training session (optional)

### Public Announcement (if public repo)

- [ ] Share on LinkedIn/Twitter
- [ ] Post in Azure/Kubernetes communities
- [ ] Submit to awesome-lists (if applicable)

---

## 📊 Post-Launch Monitoring

### Week 1

- [ ] Monitor GitHub issues
- [ ] Watch for user feedback
- [ ] Check analytics (if enabled)
- [ ] Respond to questions

### Month 1

- [ ] Review usage patterns
- [ ] Collect feedback from early adopters
- [ ] Plan improvements for v1.1.0
- [ ] Update documentation based on common questions

---

## 🔄 Ongoing Maintenance

### Monthly

- [ ] Check for Microsoft docs updates
- [ ] Update AKS best practices
- [ ] Review and merge community PRs
- [ ] Update example configurations

### Quarterly

- [ ] Review all documentation
- [ ] Update version requirements
- [ ] Test with latest GitHub Copilot
- [ ] Plan major version updates

### Yearly

- [ ] Major version release (if needed)
- [ ] Architecture review
- [ ] Survey users for feedback

---

## ✅ Final Pre-Launch Checklist

Before marking repository as template:

- [ ] All placeholder text updated
- [ ] All links verified
- [ ] License file correct
- [ ] Contributing guidelines clear
- [ ] Security policy documented
- [ ] README.md complete
- [ ] Example configurations tested
- [ ] Decision guides reviewed
- [ ] Workflows tested
- [ ] Branch protection configured
- [ ] Repository settings configured
- [ ] Initial release created
- [ ] Template repository checkbox enabled ✅

---

## 🎉 Launch!

Once all items above are complete:

1. ✅ Enable "Template repository" in settings
2. 🚀 Share with intended audience
3. 📢 Announce availability
4. 📊 Monitor usage and feedback

**Your template is ready for users to start generating AKS infrastructure!**

---

## 📞 Need Help?

- Review [CONTRIBUTING.md](../CONTRIBUTING.md)
- Check [GitHub Template Documentation](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-template-repository)
- Open an issue for questions
