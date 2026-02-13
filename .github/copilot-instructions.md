# GitHub Copilot Instructions

**Purpose:** This file contains instructions for GitHub Copilot agents working in this repository.

---

## Overview

This repository uses GitHub Copilot to assist with Azure infrastructure development. Instructions and best practices will be added incrementally as the project evolves.

## Workflow Guidelines

### Development Workflow (New Features, Infrastructure Changes)

When developing new features or making infrastructure changes:

- Follow standard GitHub workflow (issue → branch → commit → PR → review → merge)
- Use conventional commit format: `<type>(scope): description`
- Reference issues in commits: `Fixes #<issue-number>`
- Request Copilot review before merging PRs

### Administrative Tasks (Cleanup, Configuration, Documentation)

For administrative tasks (infrastructure cleanup, artifact creation, documentation updates):

- May work directly on main branch when appropriate
- Still use conventional commit format
- Document rationale in commit messages
- Examples: destroying test infrastructure, creating GHCP artifacts, updating instructions

## Terraform Infrastructure Management

### Terraform Destroy Workflow

When destroying Terraform infrastructure in this repository:

1. **ALWAYS use the destroy wrapper script**: `infra/scripts/destroy-with-recovery.sh`
   - The script handles pre-flight checks, error recovery, and structured logging
   
2. **Follow dependency order**: Destroy spoke deployments BEFORE hub deployments
   - Example: `spoke-aks-prod` must be destroyed before `hub-eastus`
   
3. **Pre-flight checks are mandatory**:
   - Verify Azure authentication (`az account show`)
   - Validate backend resources exist (check `*.tfbackend` files)
   - Sync state with `terraform plan` (should show no changes)

4. **Use path-specific instructions**: See `.github/instructions/terraform-destroy.instructions.md` for detailed error recovery patterns

5. **Error recovery**: If destroy fails, consult the instruction file for common patterns before manual intervention

### GHCP Artifact Structure

This repository uses Minimum Viable Configuration (MVC) approach:

- **Repository-wide instructions**: `.github/copilot-instructions.md` (this file)
- **Path-specific instructions**: `.github/instructions/*.instructions.md`
- **Automation scripts**: `infra/scripts/`
- **No skills created** unless workflows are reusable across multiple repositories

---

**Note:** Instructions are added incrementally based on project requirements. Always check path-specific instruction files for detailed guidance on specific operations.
