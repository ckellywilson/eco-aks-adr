---
name: validate-terraform
description: Validate Terraform code against Azure Verified Modules standards and best practices. Use this when asked to validate infrastructure code, check for errors, verify AVM compliance, or run pre-commit checks.
license: MIT
---

# Validate Terraform Skill

## Purpose

This skill automates comprehensive validation of Terraform code against Terraform best practices and Azure-specific requirements. It ensures code quality before commits and pull requests.

## When to Use This Skill

Invoke this skill when the user requests:
- "Validate my Terraform code"
- "Run validation checks"
- "Check Terraform for errors"
- "Validate against best practices"
- "Run pre-commit checks"
- "Verify code quality"

## Task

Execute all required validation steps for Terraform infrastructure code, including formatting, syntax validation, and security scanning.

## Prerequisites

Before executing this skill:
1. **REQUIRED**: Terraform code exists in the workspace (at least one `.tf` file)
2. Terraform is installed and available on PATH
3. Optional validation tools:
   - `tfsec` for security scanning (recommended)
   - `checkov` for additional policy checks (optional)
4. Working directory contains Terraform configuration files

**⚠️ CRITICAL**: This skill will NOT run validation on template repositories without Terraform code. Validation checks require actual `.tf` files to validate.

## Instructions

### Step 1: Determine Validation Scope

Identify what needs to be validated and set the target directory:

```bash
# Prompt user for directory to validate
echo "Which directory should be validated?"
echo "Options: hub/, spoke-aks/, or . (current directory)"
read -p "Directory [default: .]: " user_target_directory

# Set target directory with default
target_directory="${user_target_directory:-.}"

# Verify directory exists
if [ ! -d "$target_directory" ]; then
  echo "❌ Error: Directory '$target_directory' does not exist"
  exit 1
fi

echo "✓ Validating directory: $target_directory"
```

### Step 2: Check Prerequisites

Verify required tools are available and Terraform code exists:

```bash
# Check if Terraform files exist in the workspace
echo "Checking for Terraform files..."
TF_FILES=$(find "$target_directory" -name "*.tf" -type f 2>/dev/null | wc -l | tr -d '[:space:]')

if [ "$TF_FILES" -eq 0 ]; then
  echo "Terraform validation requires at least one .tf file in the target directory."
  echo "Please generate or copy your Terraform configuration into this directory"
  echo "before running validation."
  echo ""
  echo "If this is a template or starter repository, run your project's code generation"
  echo "or scaffolding process to create Terraform files, then re-run this validation."
  echo ""
  echo "Skipping validation because there is no Terraform code to validate."
  return 1 2>/dev/null || exit 1
fi

echo "✓ Found $TF_FILES Terraform file(s)"

# Check Terraform installation
terraform version

# Check for validation tools (optional but recommended)
command -v tfsec >/dev/null 2>&1 && echo "✓ tfsec available (recommended)" || echo "⚠ tfsec not installed (recommended for security scanning)"
command -v checkov >/dev/null 2>&1 && echo "✓ checkov available" || echo "  checkov not installed (optional)"
```

### Step 3: Run Terraform Format Check

Format checking ensures consistent code style:

```bash
# Navigate to target directory
cd "$target_directory"

# Check formatting (read-only check)
echo "Running Terraform format check..."
terraform fmt -check -recursive -diff

# If format check fails, optionally auto-fix
if [ $? -ne 0 ]; then
  echo "Formatting issues detected. Running terraform fmt to fix..."
  terraform fmt -recursive
  echo "✓ Code formatted successfully"
fi
```

**Why this matters**: Consistent formatting improves readability and prevents spurious diffs in version control.

### Step 4: Run Terraform Validate

Syntax and configuration validation:

```bash
# Initialize if needed (required for validation)
if [ ! -d ".terraform" ]; then
  echo "Initializing Terraform..."
  terraform init -backend=false
fi

# Run validation
echo "Running Terraform validate..."
terraform validate

if [ $? -eq 0 ]; then
  echo "✓ Terraform validation passed"
else
  echo "✗ Terraform validation failed"
  echo "Review errors above and fix configuration issues"
  exit 1
fi
```

**Why this matters**: Catches syntax errors, invalid references, and configuration problems before deployment.

### Step 5: Run Security Scanning

Execute security scanning to identify potential security issues:

```bash
echo "Running security scans..."

# Run tfsec if available (recommended)
if command -v tfsec >/dev/null 2>&1; then
  echo "Running tfsec security scan..."
  tfsec . --minimum-severity MEDIUM
  
  if [ $? -eq 0 ]; then
    echo "✓ tfsec security scan passed"
  else
    echo "⚠ tfsec found security issues - review and address"
  fi
else
  echo "⚠ tfsec not installed (recommended for security scanning)"
  echo "  Install: https://github.com/aquasecurity/tfsec"
fi

# Run checkov if available (optional)
if command -v checkov >/dev/null 2>&1; then
  echo "Running checkov policy checks..."
  checkov -d . --compact --quiet
  
  if [ $? -eq 0 ]; then
    echo "✓ checkov policy checks passed"
  else
    echo "ℹ checkov found policy violations - review if applicable"
  fi
else
  echo "  checkov not installed (optional)"
fi
```

**Why this matters**: Identifies security vulnerabilities and compliance issues before deployment.

### Step 6: Verify AVM Module Usage

Check that Azure Verified Modules are being used correctly:

```bash
echo "Verifying AVM module usage..."

# Check for AVM modules
echo "- Checking for AVM module sources..."
if grep -r 'source.*=.*"Azure/avm-' "$target_directory" 2>/dev/null | grep -q '.tf'; then
  echo "  ✓ AVM modules found"
  
  # Check for version pinning
  echo "- Verifying module version pinning..."
  unversioned_modules=$(grep -r 'source.*=.*"Azure/avm-' "$target_directory" 2>/dev/null | grep '.tf' | grep -v 'version.*=' || true)
  
  if [ -z "$unversioned_modules" ]; then
    echo "  ✓ All AVM modules have versions pinned"
  else
    echo "  ✗ Error: Some AVM modules missing version pins:"
    echo "$unversioned_modules"
    exit 1
  fi
  
  # Check for telemetry
  echo "- Checking telemetry setting..."
  if grep -r 'enable_telemetry.*=.*true' "$target_directory" 2>/dev/null | grep -q '.tf'; then
    echo "  ✓ Telemetry enabled on AVM modules"
  else
    echo "  ⚠ Warning: enable_telemetry should be set to true for AVM modules"
  fi
else
  echo "  ℹ No AVM modules detected (this is OK if using other modules)"
fi
```

**Why this matters**: Ensures AVM modules follow best practices for versioning and telemetry.
else
  echo "✗ TFLint checks failed"
  echo "⚠ Review security findings and address as needed"
fi
```

**Why this matters**: Identifies security vulnerabilities and compliance issues before deployment.

### Step 7: Generate Validation Report

Create a summary of all validation results:

```bash
echo ""
echo "============================================="
echo "  Terraform Validation Report"
echo "============================================="
echo ""
echo "✓ Code formatted correctly (terraform fmt)"
echo "✓ Syntax validation passed (terraform validate)"

if command -v tfsec >/dev/null 2>&1; then
  echo "✓ Security scan completed (tfsec)"
else
  echo "⚠ Security scan skipped (tfsec not installed)"
fi

if grep -r 'source.*=.*"Azure/avm-' "$target_directory" 2>/dev/null | grep -q '.tf'; then
  echo "✓ AVM module usage verified"
fi

echo ""
echo "PR Readiness Checklist:"
echo "  ☐ All AVM modules have pinned versions (~> syntax)"
echo "  ☐ enable_telemetry = true on all AVM modules"
echo "  ☐ All variables have descriptions"
echo "  ☐ No hardcoded values (use variables)"
echo "  ☐ Proper resource naming conventions"
echo "  ☐ No secrets in code"
echo ""
echo "✅ All automated validation checks passed!"
echo "Review the checklist above before creating your PR."
echo ""
```

**Why this matters**: Provides a clear summary of validation status and remaining manual checks.

## Expected Output

After successfully running this skill, the user should see:

1. ✅ Terraform formatting verified
2. ✅ Syntax validation passed
3. ✅ Security scanning completed (if tools available)
4. ✅ AVM module usage verified (if AVM modules present)
5. 📋 PR readiness checklist

The code is ready for commit and PR creation.

## Error Handling

### No Terraform Files Found

If the target directory contains no `.tf` files:

```
⚠ No Terraform files found in directory: [directory]

This skill validates Terraform code, but no .tf files exist.
Please generate or copy your Terraform configuration first.
```

**Resolution**: Generate Terraform code or navigate to the correct directory.

### Validation Failures

If any validation step fails, the skill will:
1. Clearly identify which check failed
2. Show the specific error messages
3. Provide guidance on how to fix the issues
4. Exit with non-zero status to prevent proceeding

## Best Practices

1. **Run Early and Often**: Validate after each significant change
2. **Fix Issues Immediately**: Don't accumulate validation errors
3. **Review Security Findings**: Address security issues before creating PRs
4. **Use All Available Tools**: Install tfsec for better security coverage
5. **Follow the Checklist**: Verify all manual items before PR creation

## Integration with Workflow

This skill integrates with the standard development workflow:

1. **After Code Generation**: Validate immediately after generating infrastructure code
2. **Before Commits**: Run validation before each commit
3. **Before PR Creation**: Final validation before opening pull request
4. **After Feedback**: Re-validate after addressing review comments

## Notes

- This skill focuses on **consuming** Azure Verified Modules, not contributing to them
- The validation checks ensure generated code follows Terraform and Azure best practices
- Security scanning with tfsec is highly recommended but optional
- All AVM modules must have pinned versions and telemetry enabled
2. Create a pull request
3. Request Copilot review

Command to commit:
git add .
git commit -m "feat: implement infrastructure with AVM compliance"
```

#### If Checks Fail:
```
❌ Validation failed with the following issues:

[List specific failures]

To fix these issues:
1. Review the error messages above
2. Consult .github/instructions/azure-verified-modules-terraform.instructions.md
3. Make necessary corrections
4. Run validation again: "Validate my Terraform code"

Common fixes:
- Format issues: terraform fmt -recursive
- Syntax errors: Check variable references and resource dependencies
- AVM compliance: Ensure enable_telemetry = true and versions pinned
```

## Success Criteria

Validation is complete when:
- [ ] `terraform fmt -check` passes (no formatting issues)
- [ ] `terraform validate` passes (no syntax errors)
- [ ] Security scans run (tfsec recommended)
- [ ] AVM module usage verified (telemetry, versions, sources)
- [ ] User provided clear next steps

## Common Issues and Solutions

### Issue: No Terraform Files Found
**Solution**: 
- Ensure you're in the correct directory containing `.tf` files
- Generate infrastructure code first before running validation
- Check that Terraform working directory exists (e.g., `hub-*/`, `spoke-*/`)

### Issue: Terraform Init Fails
**Solution**: 
- Check that `providers.tf` and `terraform.tf` are properly configured
- Verify network connectivity for provider downloads
- Use `-backend=false` for validation-only init

### Issue: Module Source Not Found
**Solution**:
- Verify module names and versions exist in Terraform Registry
- Check `https://registry.terraform.io/modules/Azure/{module}/azurerm/versions`
- Ensure proper format: `Azure/avm-{type}-{service}-{resource}/azurerm`

### Issue: Security Scan False Positives
**Solution**:
- Review each finding for actual risk
- Document justified exceptions
- Focus on HIGH and CRITICAL severity issues

### Issue: Version Constraint Conflicts
**Solution**:
- Review all `version` constraints in module blocks
- Check provider version requirements
- Update to compatible versions following AVM guidance

## Integration with Workflow

This skill integrates with the repository workflow from `.github/copilot-instructions.md`:

**Pre-Commit Stage:**
```
Developer makes changes → Runs "Validate Terraform" skill → Fixes issues → Commits
```

**Pre-PR Stage:**
```
Feature branch ready → Runs "Validate Terraform" skill → Creates PR → Requests Copilot review
```

**Required for PR Approval:**
- All validation checks must pass
- Security issues addressed
- AVM compliance verified (if using AVM modules)

## Resources Referenced

- `.github/instructions/terraform-azure-best-practices.instructions.md` - Terraform validation requirements
- `.github/instructions/generate-modern-terraform-code-for-azure.instructions.md` - Terraform best practices
- Terraform CLI documentation
- Azure Verified Modules documentation

## Notes

- This skill focuses on **consuming** AVM modules, not contributing to them
- Security scanning (tfsec) is highly recommended
- Validation should be run before every commit and PR
- This skill can be run multiple times during development
- Validation is non-destructive - it never modifies infrastructure, only checks code
