# Contributing to AKS Landing Zone Template

Thank you for your interest in contributing! This is a minimal template repository to help users build AKS infrastructure with GitHub Copilot assistance.

> **Note:** This template has been simplified. Previous versions contained extensive prompts, documentation, and examples in `.github/prompts/`, `.github/docs/`, `.github/examples/`, and `.github/instructions/` directories. These have been removed to provide a minimal starting point. Historical content is available in git history if needed.

## 🎯 What We Accept

### ✅ DO Submit PRs With:

- **Template improvements** - Better structure, clearer instructions
- **Documentation updates** - Corrections, clarifications, enhancements
- **Bug fixes** - Errors in documentation, broken links, typos
- **GitHub Copilot configuration** - Improvements to `.github/copilot-instructions.md`
- **Workflow improvements** - Better CI/CD, automation enhancements
- **Dependency updates** - Keep dependencies current

### ❌ Do NOT Submit PRs With:

- **Your generated infrastructure code** - This is a template, not an infrastructure repository
- **Your environment-specific configurations** - Keep your configs private
- **Your company's infrastructure details** - This is a public template
- **Terraform state files** - Never commit state files
- **Azure credentials or secrets** - Never commit sensitive information
- **Generated files from using the template** - Only template files belong here

---

## 🚀 Getting Started

### Prerequisites

1. **Fork this repository** (not "Use this template" - that's for end users)
2. **Clone your fork**:
   ```bash
   git clone https://github.com/YOUR-USERNAME/aks-lz-ghcp.git
   cd aks-lz-ghcp
   ```
3. **Set up upstream remote**:
   ```bash
   git remote add upstream https://github.com/ORIGINAL-ORG/aks-lz-ghcp.git
   ```
4. **Create a branch**:
   ```bash
   git checkout -b feature/your-feature-name
   ```

---

## 📝 Contribution Guidelines

### Documentation Updates

When updating documentation:

- **Use clear language** - Make it easy to understand
- **Include examples** - Show how things work
- **Update related docs** - Keep documentation consistent
- **Test instructions** - Verify they work as described
- **Follow markdown style** - Use consistent formatting

### GitHub Copilot Configuration

When updating `.github/copilot-instructions.md`:

- **Test with GitHub Copilot** - Ensure instructions are effective
- **Keep it minimal** - Only essential guidance
- **Document decisions** - Explain why instructions are needed
- **Follow best practices** - Align with GitHub Copilot guidelines

---

## 🧪 Testing Your Changes

### Test Documentation Changes

```bash
# Check for broken links
npm install -g markdown-link-check
find . -name "*.md" -exec markdown-link-check {} \;

# Check spelling (optional)
npm install -g cspell
find . -name "*.md" -exec cspell {} \;
```

### Validate Markdown Formatting

```bash
# Ensure consistent markdown style
npm install -g markdownlint-cli
markdownlint '**/*.md'
```

---

## 📋 Pull Request Process

### 1. Prepare Your PR

- [ ] Create a feature branch (`feature/improve-cilium-docs`)
- [ ] Make your changes
- [ ] Test your changes (see Testing section above)
- [ ] Update related documentation
- [ ] Commit with clear messages (see Commit Guidelines below)
- [ ] Push to your fork
- [ ] Create a pull request

### 2. PR Title Format

Use conventional commit format:

```
<type>(<scope>): <description>

Examples:
feat(template): add new GitHub Copilot instructions
docs(readme): update getting started guide
fix(contributing): correct broken link
chore(deps): update dependabot configuration
```

**Types:**
- `feat` - New features
- `fix` - Bug fixes
- `docs` - Documentation changes
- `chore` - Maintenance tasks
- `refactor` - Code restructuring
- `test` - Test updates

### 3. PR Description Template

```markdown
## Description
Brief description of changes

## Motivation
Why is this change needed? What problem does it solve?

## Changes
- List of specific changes
- Update to X file
- New feature Y

## Testing
How did you test these changes?

## References
Links to relevant documentation or issues

## Checklist
- [ ] Tested changes
- [ ] Updated related documentation
- [ ] No sensitive information included
- [ ] Follows contribution guidelines
```

### 4. Review Process

- Maintainers will review your PR within 3-5 business days
- Address any requested changes
- Once approved, maintainers will merge your PR
- Your contribution will be included in the next release

---

## 📏 Code Standards

### Markdown Style

- Use ATX-style headers (`#`, `##`, `###`)
- Include blank lines around headers
- Use fenced code blocks with language identifiers
- Keep lines under 120 characters where possible
- Use reference-style links for readability

### File Organization

```
.github/
├── copilot-instructions.md  # GitHub Copilot configuration
└── dependabot.yml          # Dependency update automation

docs/                        # Project documentation
infra/                       # Infrastructure code
scripts/                     # Automation scripts
```

---

## 🐛 Reporting Issues

### Before Creating an Issue

1. **Search existing issues** - Check if it's already reported
2. **Verify it's a template issue** - Not an issue with your generated code
3. **Check documentation** - Ensure it's not expected behavior
4. **Test with latest version** - Use the latest template version

### Issue Template

```markdown
**Issue Type**: Bug / Feature Request / Documentation / Question

**Description**
Clear description of the issue

**Location**
Which file(s) are affected?
- README.md
- .github/copilot-instructions.md

**Expected Behavior**
What should happen?

**Actual Behavior**
What actually happens?

**Steps to Reproduce**
1. Open file
2. Follow instructions
3. See error

**Environment**
- GitHub Copilot version:
- VS Code version:
- Template version:

**Screenshots**
If applicable, add screenshots
```

---

## 📚 Resources

### Microsoft Documentation
- [Azure Kubernetes Service](https://learn.microsoft.com/azure/aks/)
- [AKS Baseline Architecture](https://learn.microsoft.com/azure/architecture/reference-architectures/containers/aks/baseline-aks)
- [Azure Verified Modules](https://aka.ms/avm)

### GitHub Resources
- [GitHub Copilot Documentation](https://docs.github.com/copilot)
- [GitHub Actions](https://docs.github.com/actions)

### Terraform Resources
- [Terraform AzureRM Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)

---

## 🤝 Code of Conduct

### Our Standards

- **Be respectful** - Treat everyone with respect
- **Be collaborative** - Work together to improve the template
- **Be constructive** - Provide helpful feedback
- **Be patient** - Remember everyone has different skill levels
- **Be inclusive** - Welcome diverse perspectives

### Unacceptable Behavior

- Harassment or discriminatory language
- Personal attacks or insults
- Trolling or inflammatory comments
- Publishing others' private information
- Other unethical or unprofessional conduct

---

## 📄 License

By contributing, you agree that your contributions will be licensed under the same license as this project (MIT License).

---

## 🙏 Thank You!

Your contributions help make AKS deployments better for everyone. We appreciate your time and effort!

**Questions?** Open an issue or reach out to the maintainers.

---

## 📞 Contact

- **Issues**: [GitHub Issues](https://github.com/ckellywilson/aks-lz-ghcp/issues)
- **Discussions**: [GitHub Discussions](https://github.com/ckellywilson/aks-lz-ghcp/discussions)
- **Security Issues**: See [SECURITY.md](SECURITY.md)
