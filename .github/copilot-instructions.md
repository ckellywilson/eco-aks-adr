# GitHub Copilot Workflow Instructions

**These instructions are automatically applied to all GitHub Copilot interactions in this repository.**

---

## 🔄 Required Development Workflow

GitHub Copilot MUST enforce the following workflow for ALL code changes:

### 1. **Feature Branch Creation**

Before making ANY changes:

```bash
# Create a feature branch with descriptive name
git checkout -b feature/description
# OR
git checkout -b fix/issue-number-description
```

**Branch Naming Convention:**
- `feature/*` - New features or enhancements
- `fix/*` - Bug fixes
- `chore/*` - Maintenance, docs, or non-functional changes
- `docs/*` - Documentation-only changes

**❌ NEVER work directly on `main` branch**

---

### 2. **Issue Creation/Update**

Before implementing changes, ensure an issue exists:

**For New Work:**
```bash
# Prompt user to create issue
gh issue create --title "Brief description" --body "Detailed context"
```

**For Existing Issues:**
```bash
# Link work to existing issue
gh issue view ISSUE_NUMBER
```

**Issue Requirements:**
- ✅ Clear, descriptive title
- ✅ Acceptance criteria or expected outcome
- ✅ Labels (e.g., `enhancement`, `bug`, `documentation`)
- ✅ Milestone (if applicable)

**When generating code, ASK USER:**
> "Which issue does this work address? (Provide issue number or I'll help create one)"

---

### 3. **Code Implementation & Validation**

When generating infrastructure code:

#### Three-Tiered Validation Approach

**Tier 1: Pre-Commit (REQUIRED - Every Commit)**

Fast checks that run in 5-10 seconds:

```bash
# Format Terraform code
terraform fmt -recursive

# Validate syntax
terraform validate

# Security scan (if tfsec installed)
tfsec . --minimum-severity MEDIUM

# Check for secrets (if gitleaks installed)
gitleaks detect --source . --verbose
```

**Tier 2: Pre-PR (REQUIRED - Before Creating Pull Request)**

Comprehensive validation that runs in 1-3 minutes:

```bash
# Run linting and security checks (from each Terraform working directory)
# Navigate to your Terraform directory first (e.g., cd infra/terraform/hub-eastus/)
terraform fmt -check -recursive
terraform validate
tfsec . --minimum-severity MEDIUM
```

**Note:** These commands must be run from within a Terraform working directory containing `.tf` files (e.g., `hub-*/`, `spoke-*/`). The template repository itself contains no Terraform code to validate.

**Tier 3: CI/CD (AUTOMATED - Runs in GitHub Actions/Azure DevOps)**

Full validation in 5-15 minutes - runs automatically in pipelines with terraform plan, policy scans, and well-architected checks.

**Note:** Tier 3 is automated in CI/CD pipelines after you generate them. You can also run comprehensive validation manually at any time for a full validation check.

#### Terraform-Specific Requirements

- ✅ Consume Azure Verified Modules (AVM) where available
- ✅ Follow naming conventions from `.github/instructions/`
- ✅ Include meaningful variable descriptions
- ✅ Use `locals {}` for computed values
- ✅ Add comments explaining complex logic
- ✅ Never commit `.tfstate` files or secrets

#### Commit Message Format

Use **Conventional Commits**:

```
<type>(scope): <subject>

<body>

Fixes #<issue-number>
```

**Examples:**
```bash
feat(spoke-aks): add Azure CNI Overlay support with Cilium

- Implemented network_profile with overlay mode
- Added Cilium data plane configuration
- Updated network policy to use Cilium

Fixes #42
```

```bash
fix(hub): correct firewall policy association

- Fixed firewall policy resource dependency
- Added explicit depends_on for subnet association

Fixes #38
```

**Types:** `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `perf`

---

### 4. **Pull Request Creation**

After committing and pushing:

```bash
# Push feature branch
git push -u origin feature/description

# Create PR (GitHub CLI)
gh pr create --title "Brief description" --fill
```

#### PR Requirements

**Title Format:**
```
<type>(scope): Brief description (fixes #issue-number)
```

**PR Description MUST Include:**
- ✅ **What** - What changes were made
- ✅ **Why** - Why these changes were needed (link to issue)
- ✅ **How** - How the changes work
- ✅ **Testing** - Validation steps performed
- ✅ **Checklist** - Pre-merge verification items
- ✅ **Terraform Plan Output** (if applicable)

**Template:**
```markdown
## Changes
<!-- What was changed -->

## Related Issue
Fixes #<issue-number>

## Testing
<!-- How changes were validated -->
- [ ] terraform fmt -check
- [ ] terraform validate
- [ ] terraform plan (no errors)
- [ ] Security scan passed
- [ ] Manual testing in dev environment

## Terraform Plan
\```
<terraform plan output>
\```

## Review Checklist
- [ ] Code follows best practices
- [ ] Variables have descriptions
- [ ] Sensitive values properly marked
- [ ] No hardcoded values
- [ ] Documentation updated
```

---

### 5. **GitHub Copilot Code Review**

**ALWAYS request Copilot review before merging:**

In the PR, comment:
```
@github-copilot review this PR for:
- Terraform best practices
- Azure security considerations
- AVM compliance
- Potential issues or improvements
```

**Wait for Copilot's review feedback before proceeding**

**After Copilot Review:**
- ✅ Address any issues identified
- ✅ Push updates if needed
- ✅ Re-request review if significant changes made

---

### 6. **Merge Process**

**Pre-Merge Verification:**

```bash
# Ensure branch is up to date
git fetch origin main
git rebase origin/main

# Final validation
terraform fmt -check -recursive
terraform validate
```

**Merge Strategy:**
- Use **Squash and merge** for clean history
- Use **Rebase and merge** for maintaining commit history
- ❌ Avoid merge commits unless necessary

**Post-Merge:**
```bash
# Delete feature branch (local and remote)
git branch -d BRANCH_NAME
git push origin --delete BRANCH_NAME

# Close related issue (if not auto-closed)
gh issue close ISSUE_NUMBER --comment "Resolved in #PR_NUMBER"
```

---

## 🛡️ Security & State Management

### NEVER Commit:
- ❌ `.tfstate` or `.tfstate.backup` files
- ❌ `terraform.tfvars` with real values
- ❌ Azure credentials or service principal secrets
- ❌ SSH keys or certificates
- ❌ Any files containing sensitive data

### State Management Rules:
- ✅ Use Azure Storage for remote state
- ✅ Enable state locking
- ✅ Use separate state files per environment
- ✅ Never share state files in repository

---

## 📋 GitHub Copilot Prompts

When user asks to implement changes, GitHub Copilot should:

1. **Check current branch:**
   ```
   What branch are you currently on? You need to create a feature branch.
   ```

2. **Verify issue exists:**
   ```
   What issue number does this address? (Or should I help create one?)
   ```

3. **After generating code:**
   ```
   Please run these validation commands before committing:
   - terraform fmt -recursive
   - terraform validate
   - tfsec . --minimum-severity MEDIUM
   
   Ready to commit? Use this format:
   feat(scope): description
   
   Fixes #ISSUE_NUMBER
   ```

4. **Before PR creation:**
   ```
   Ready to create a PR? I'll help you:
   1. Push your branch
   2. Create PR with proper description
   3. Request Copilot review
   ```

5. **Before merge:**
   ```
   Before merging:
   1. Have you received Copilot's review?
   2. Are all checks passing?
   3. Is the branch up to date with main?
   ```

---

## 🎯 Workflow Checklist Template

**Copy this for each development task:**

```
Development Task: [Brief Description]
Issue: #___

[ ] 1. Created feature branch (feature/*)
[ ] 2. Issue created/updated with clear requirements
[ ] 3. Code implemented following best practices
[ ] 4. Pre-commit validation passed:
    [ ] terraform fmt
    [ ] terraform validate
    [ ] tfsec security scan
[ ] 5. Committed with conventional commit message
[ ] 6. Pushed to remote branch
[ ] 7. PR created with complete description
[ ] 8. Requested GitHub Copilot review
[ ] 9. Addressed Copilot feedback
[ ] 10. All PR checks passing
[ ] 11. PR approved and merged
[ ] 12. Feature branch deleted
[ ] 13. Issue closed
```

---

## 🚨 Enforcement Rules

GitHub Copilot MUST:

1. **Refuse to generate code on `main` branch**
   - Response: "Please create a feature branch first: `git checkout -b feature/description`"

2. **Ask for issue number before generating significant code**
   - Response: "Which issue does this address? (Provide # or I'll help create one)"

3. **Remind about Tier 1 validation before commits**
   - Response: "Before committing, run: `terraform fmt -recursive && terraform validate`"

4. **Remind about Tier 2 validation before PR creation**
   - Response: "Before creating the PR, run: `terraform fmt -check -recursive && terraform validate && tfsec . --minimum-severity MEDIUM`"

5. **Prompt for PR creation after commits**
   - Response: "Ready to create a PR? Let me help with that."

6. **Require Copilot review before merge suggestions**
   - Response: "Have you requested @github-copilot review? This is required."

---

## 📚 Additional Best Practices

### Small, Focused PRs
- ✅ One logical change per PR
- ✅ Keep PRs under 400 lines when possible
- ✅ Split large features into multiple PRs

### Code Quality
- ✅ Self-documenting code with clear naming
- ✅ Comments for complex logic only
- ✅ Consistent formatting (automated)
- ✅ No commented-out code

### Collaboration
- ✅ Respond to review comments promptly
- ✅ Be open to feedback and suggestions
- ✅ Keep discussions professional and constructive

---

## 🔗 Quick Reference

```bash
# Complete workflow in one script
git checkout -b feature/my-change
# ... make changes ...
terraform fmt -recursive && terraform validate
git add .
git commit -m "feat(scope): description

Fixes #ISSUE_NUMBER"
git push -u origin feature/my-change
gh pr create --fill
# Request Copilot review in PR
# Wait for approval
# Merge PR
gh pr merge --squash --delete-branch
```

---

**These instructions are automatically applied. GitHub Copilot will guide you through this workflow for every change.**
