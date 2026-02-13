# GitHub Copilot Instructions

Repository-wide instructions for GitHub Copilot agents. Path-specific guidance lives in `.github/instructions/*.instructions.md`.

---

## Workflow Guidelines

### Development Workflow

- Follow standard GitHub workflow (issue → branch → commit → PR → review → merge)
- Use conventional commit format: `<type>(scope): description`
- Reference issues in commits: `Fixes #<issue-number>`
- Request Copilot review before merging PRs

### Administrative Tasks

- May work directly on main branch when appropriate (cleanup, documentation, artifact updates)
- Still use conventional commit format
- Document rationale in commit messages

## GHCP Artifact Structure

This repository uses Minimum Viable Configuration (MVC) approach:

- **Repository-wide instructions**: `.github/copilot-instructions.md` (this file)
- **Path-specific instructions**: `.github/instructions/*.instructions.md`
- **Automation scripts**: `infra/scripts/`
- **No skills created** unless workflows are reusable across multiple repositories
