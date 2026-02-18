# CI/CD Landing Zone — Terraform Module

Self-hosted ACI-based Azure DevOps pipeline agents deployed in a dedicated landing zone.

## Quick Reference

| Item | Value |
|------|-------|
| **Spec** | [`.github/instructions/cicd-deploy.instructions.md`](../../../.github/instructions/cicd-deploy.instructions.md) |
| **Pipeline** | [`pipelines/cicd-deploy.yml`](../../../pipelines/cicd-deploy.yml) |
| **VNet CIDR** | `10.2.0.0/24` (self-managed) |
| **Hub dependency** | Optional — bootstrap-first pattern (hub integration added Day 2) |
| **Agent type** | Container App Jobs via [AVM CI/CD Agents module](https://registry.terraform.io/modules/Azure/avm-ptn-cicd-agents-and-runners/azurerm/latest) |
| **Auth** | UAMI (no PAT tokens) |

## Deployment

```bash
# Prerequisites: Platform KV created (hub optional at bootstrap)
cd infra/terraform/cicd
terraform init -backend-config=backend-prod.tfbackend
terraform plan -var-file=prod.tfvars -var="platform_key_vault_id=<KV_ID>"
terraform apply
```

## Bootstrap Sequence

1. **Hub deploy** (MS-hosted agents) → creates CI/CD RG + VNet + peering
2. **CI/CD deploy** (MS-hosted agents) → deploys ACI agents into hub-created VNet
3. **Manual**: Register UAMI in ADO org, create agent pool
4. **Spoke deploy** (self-hosted agents) → runs on CI/CD agent pool

## Architecture

See the [CI/CD spec](../../../.github/instructions/cicd-deploy.instructions.md) for full architecture documentation.
