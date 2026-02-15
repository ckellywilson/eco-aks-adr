# GitHub Copilot Instructions

Repository-wide instructions for GitHub Copilot agents. Path-specific guidance lives in `.github/instructions/*.instructions.md`.

---

## Workflow Guidelines

### Development Workflow (Code Changes)

**Required for ALL changes to `*.tf`, `*.yml` (pipelines), `*.sh` (scripts), or any functional code:**

- Follow standard GitHub workflow: issue → branch → commit → PR → review → merge
- Use conventional commit format: `<type>(scope): description`
- Reference issues/work items in commits: `Fixes #<issue-number>` or `AB#<work-item-id>`
- Request Copilot review before merging PRs
- **Copilot agents MUST create a feature branch** — never commit code changes directly to main
- After merge: delete feature branch (local + remote) and pull main

### Administrative Tasks (Direct to Main)

**Only for non-functional changes that don't affect infrastructure or pipeline behavior:**

- Instruction/spec files (`.github/instructions/*.instructions.md`)
- Documentation updates (`README.md`, `CONTRIBUTING.md`)
- Gitignore, editor config, MCP config changes
- Still use conventional commit format
- Document rationale in commit messages

## GHCP Artifact Structure

This repository uses Minimum Viable Configuration (MVC) approach:

- **Repository-wide instructions**: `.github/copilot-instructions.md` (this file)
- **Path-specific instructions**: `.github/instructions/*.instructions.md`
- **Automation scripts**: `infra/scripts/`
- **No skills created** unless workflows are reusable across multiple repositories
