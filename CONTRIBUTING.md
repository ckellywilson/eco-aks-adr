# Contributing to AKS Landing Zone - GitHub Copilot Prompt Template

Thank you for your interest in contributing! This template helps users generate AKS infrastructure using GitHub Copilot, and we welcome improvements to prompts, documentation, and examples.

## 🎯 What We Accept

### ✅ DO Submit PRs With:

- **Prompt improvements** - Better wording, clearer instructions, additional context
- **Documentation updates** - Corrections, clarifications, new decision guides
- **Example configurations** - New scenarios, updated best practices
- **Bug fixes** - Errors in prompts, broken links, typos
- **New features** - Additional deployment scenarios, configuration options
- **Microsoft docs updates** - Keep aligned with latest Azure/AKS best practices
- **Instruction updates** - Improved auto-apply coding standards

### ❌ Do NOT Submit PRs With:

- **Your generated Terraform code** - This is a template, not a code repository
- **Your environment-specific configurations** - Keep your secrets and configs private
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

### Prompt Updates

When updating prompts in `.github/prompts/`:

- **Test with GitHub Copilot** - Ensure prompts generate valid code
- **Follow AVM standards** - Align with Azure Verified Modules patterns
- **Include examples** - Show expected output or usage patterns
- **Document decisions** - Explain why changes improve code generation
- **Maintain placeholders** - Keep `[DECISION REQUIRED]` pattern for user input
- **Update related docs** - If prompt changes affect decision guides, update those too

**Example:**
```markdown
Before:
"Create an AKS cluster with Azure CNI"

After:
"Create an AKS cluster with Azure CNI Overlay networking using Cilium data plane"
```

### Documentation Updates

When updating documentation in `.github/docs/`:

- **Based on official Microsoft docs** - Reference microsoft.com sources
- **Include version info** - Note when features/recommendations changed
- **Update decision guides** - Keep configuration options current
- **Add compatibility info** - Document what works together
- **Include examples** - Show real-world usage patterns
- **Cross-reference** - Link to related docs and prompts

### Example Configuration Updates

When updating examples in `.github/examples/`:

- **Use realistic values** - Represent actual production scenarios
- **Include comprehensive comments** - Explain every configuration option
- **Follow naming conventions** - Use consistent resource naming
- **Validate configurations** - Ensure they work with latest AVM modules
- **Document use cases** - Clearly state when to use each example
- **Include security defaults** - Show secure configuration patterns

### Instruction Updates

When updating instructions in `.github/instructions/`:

- **Align with AVM standards** - Follow official Azure Verified Modules guidelines
- **Test with Copilot** - Verify instructions are applied correctly
- **Document patterns** - Explain coding standards and conventions
- **Include examples** - Show correct vs incorrect patterns
- **Update version references** - Keep module versions current

---

## 🧪 Testing Your Changes

### 1. Test Prompt Changes

```bash
# Create a test directory outside the template repo
mkdir -p /tmp/aks-test
cd /tmp/aks-test

# Copy your updated prompt
cp /path/to/aks-lz-ghcp/.github/prompts/spoke-aks.prompt.md .

# Open in VS Code and test with Copilot
code spoke-aks.prompt.md

# Ask Copilot to implement
# Verify the generated code follows AVM standards
```

### 2. Validate Documentation

```bash
# Check for broken links
npm install -g markdown-link-check
find .github/docs -name "*.md" -exec markdown-link-check {} \;

# Check spelling (optional)
npm install -g cspell
find .github -name "*.md" -exec cspell {} \;
```

### 3. Validate Examples

```bash
# Verify example tfvars have valid HCL syntax
terraform fmt -check .github/examples/

# Check for sensitive data
git secrets --scan .github/examples/
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
feat(prompts): add Azure CNI Overlay with Cilium option
docs(decisions): update network plugin selection guide
fix(examples): correct outbound type for egress restriction
chore(deps): update AVM module versions
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
- Update to X prompt
- New decision guide for Y

## Testing
How did you test these changes?

## Microsoft Docs References
Links to official Microsoft documentation supporting these changes

## Checklist
- [ ] Tested prompts with GitHub Copilot
- [ ] Updated related documentation
- [ ] Updated examples if needed
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

### HCL/Terraform Style

For example tfvars:
```hcl
# ============================================================================
# Section Header
# ============================================================================

# Brief description of this variable
variable_name = "value"

# Multi-line values
list_variable = [
  "item1",
  "item2",
]
```

### File Organization

```
.github/
├── prompts/              # Copilot code generation prompts
├── docs/                 # User-facing documentation
│   ├── *.md             # Decision guides, references
│   └── diagrams/        # Architecture diagrams (if any)
├── examples/            # Example configurations
│   └── *.tfvars        # Reference implementations
├── instructions/        # Auto-applied Copilot instructions
└── demos/              # Validation and testing guides
```

---

## 🐛 Reporting Issues

### Before Creating an Issue

1. **Search existing issues** - Check if it's already reported
2. **Verify it's a template issue** - Not an issue with generated code
3. **Check Microsoft docs** - Ensure it's not expected behavior
4. **Test with latest version** - Use the latest template version

### Issue Template

```markdown
**Issue Type**: Bug / Feature Request / Documentation / Question

**Description**
Clear description of the issue

**Location**
Which file(s) are affected?
- .github/prompts/spoke-aks.prompt.md
- .github/docs/aks-configuration-decisions.md

**Expected Behavior**
What should happen?

**Actual Behavior**
What actually happens?

**Steps to Reproduce**
1. Open prompt file
2. Ask Copilot to implement
3. See error

**Environment**
- GitHub Copilot version:
- VS Code version:
- Date used template:

**Screenshots**
If applicable, add screenshots

**Microsoft Docs References**
Link to relevant Microsoft documentation
```

---

## 📚 Resources

### Microsoft Documentation
- [Azure Kubernetes Service](https://learn.microsoft.com/azure/aks/)
- [AKS Baseline Architecture](https://learn.microsoft.com/azure/architecture/reference-architectures/containers/aks/baseline-aks)
- [Azure Verified Modules](https://aka.ms/avm)
- [Azure CNI Powered by Cilium](https://learn.microsoft.com/azure/aks/azure-cni-powered-by-cilium)

### Template Documentation
- [Decision Guides](.github/docs/)
- [Example Configurations](.github/examples/)
- [Prompt Templates](.github/prompts/)

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
