# AKS Landing Zone — Infrastructure as Code

This repository contains production-ready Terraform infrastructure code for an enterprise-grade private AKS landing zone on Azure. It implements a **hub-spoke network topology** across three landing zones deployed with Azure DevOps pipelines.

> 📐 See [ARCHITECTURE.md](./ARCHITECTURE.md) for an Eraser.io-ready architecture diagram description.

---

## Architecture Overview

| Landing Zone | Purpose | Pipeline |
|---|---|---|
| **CI/CD** | Self-hosted ADO pipeline agents (Container App Jobs, KEDA-scaled) | `pipelines/cicd-deploy.yml` |
| **Hub** | Centralized connectivity — Azure Firewall, Bastion, DNS Resolver, Log Analytics | `pipelines/hub-deploy.yml` |
| **Spoke (AKS)** | Private AKS cluster — CNI Overlay + Cilium, ACR, Key Vault, NGINX Ingress | `pipelines/spoke-deploy.yml` |

All spoke workload egress routes through the hub Azure Firewall. The CI/CD agents run in a dedicated VNet peered to both hub and spoke, enabling private pipeline access to the AKS API server.

---

## Repository Layout

```
infra/
├── terraform/
│   ├── cicd/           CI/CD landing zone Terraform modules
│   ├── hub/            Hub landing zone Terraform modules
│   └── spoke/          Spoke (AKS) landing zone Terraform modules
├── scripts/
│   └── destroy-with-recovery.sh   Safe destroy helper with error recovery
pipelines/
├── cicd-deploy.yml     CI/CD infrastructure pipeline
├── hub-deploy.yml      Hub infrastructure pipeline
└── spoke-deploy.yml    Spoke (AKS) infrastructure pipeline
scripts/
├── setup-ado-pipeline.sh      One-time ADO pipeline and service connection setup
└── validate-networking.sh     Post-deployment networking validation
.devcontainer/          Dev container configuration (VS Code)
ARCHITECTURE.md         Eraser.io architecture diagram source
```

---

## Prerequisites

Before deploying, ensure you have:

| Requirement | Notes |
|---|---|
| **Azure subscription** | Owner or Contributor + User Access Administrator (spoke creates role assignments) |
| **Azure CLI** | `az login` authenticated to the target subscription |
| **Terraform** | v1.5+ |
| **Azure DevOps organization** | With project created |
| **ADO Personal Access Token (PAT)** | Scopes: `Build (Read & Execute)`, `Code (Read)`, `Work Items (Read & Write)` |
| **`jq`, `ssh-keygen`, `curl`** | Required by `setup-ado-pipeline.sh` |

---

## Step 1 — Configure tfvars

Each landing zone has a `.example` file showing all required variables.

```bash
# Copy and fill in each example file
cp infra/terraform/cicd/prod.tfvars.example   infra/terraform/cicd/prod.tfvars
cp infra/terraform/hub/prod.tfvars.example    infra/terraform/hub/prod.tfvars
cp infra/terraform/spoke/prod.tfvars.example  infra/terraform/spoke/prod.tfvars

# Copy backend configuration files
cp infra/terraform/cicd/backend-prod.tfbackend.example   infra/terraform/cicd/backend-prod.tfbackend
cp infra/terraform/hub/backend-prod.tfbackend.example    infra/terraform/hub/backend-prod.tfbackend
cp infra/terraform/spoke/backend-prod.tfbackend.example  infra/terraform/spoke/backend-prod.tfbackend
```

At minimum, set these values in each `prod.tfvars`:

| Variable | Description | Example |
|---|---|---|
| `subscription_id` | Azure subscription ID | `az account show --query id -o tsv` |
| `location` | Azure region | `eastus2` |
| `environment` | Environment tag | `prod` |

In `infra/terraform/cicd/prod.tfvars`, also set:
```hcl
ado_organization_url = "https://dev.azure.com/your-org"
ado_agent_pool_name  = "aci-cicd-pool"
```

> **Hub integration variables** (prefixed `hub_*`) in `cicd/prod.tfvars` are left empty at bootstrap. They are populated after the hub is deployed (Step 6).

---

## Step 2 — One-Time ADO Setup

`scripts/setup-ado-pipeline.sh` automates the full ADO and Azure configuration:

- Creates an App Registration + Service Principal per landing zone
- Grants RBAC roles (Contributor, Storage Blob Data Contributor; User Access Administrator for spoke/CI/CD)
- Creates ADO service connections using Workload Identity Federation (no stored secrets)
- Creates federated credentials on the App Registrations
- Creates Terraform state storage accounts + blob containers
- Creates a platform Key Vault and SSH key pair for jump box VMs
- Creates pipeline definitions in ADO
- Sets the `PLATFORM_KV_ID` pipeline variable automatically

```bash
export ADO_ORG="your-org"
export ADO_PROJECT="your-project"
export AZURE_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
export AZURE_DEVOPS_PAT="<your-pat>"

./scripts/setup-ado-pipeline.sh
```

> The script is **idempotent** — safe to re-run. It checks for existing resources before creating.
> Repository type (GitHub vs. ADO Git) is auto-detected from `git remote get-url origin`.

After the script completes:
- Backend config files (`backend-prod.tfbackend`) are populated with the created storage account names
- `PLATFORM_KV_ID` is set as a pipeline variable on each pipeline

---

## Step 3 — Deploy CI/CD (Bootstrap)

The CI/CD landing zone deploys **first**, before the hub exists. On first run, use Microsoft-hosted agents.

In ADO: **Pipelines → cicd-deploy → Run pipeline**

Set the parameter:
```
useSelfHosted: false   ← required on first run (self-hosted agents don't exist yet)
```

This deploys:
- CI/CD VNet + subnets + NAT Gateway
- Container App Job environment with KEDA-scaled ADO agents (`aci-cicd-pool`)
- Module-managed ACR with ACR Tasks (auto-rebuilds agent image)
- Private endpoints for state storage account and platform Key Vault
- CI/CD-owned private DNS zones (for bootstrap before hub)

---

## Step 4 — Register UAMI in ADO (Manual, One-Time)

After the CI/CD pipeline completes, the Container App Job agents need to authenticate with ADO using a managed identity. This requires a **one-time manual registration**.

1. Get the UAMI client ID from the pipeline output or:
   ```bash
   cd infra/terraform/cicd
   terraform output agent_uami_client_id
   ```

2. In ADO: **Organization Settings → Users → Add users**
   - Add the UAMI by its client ID
   - Set access level: `Basic`

3. In ADO: **Organization Settings → Permissions → Project Collection Service Accounts → Members → Add**
   - Add the UAMI identity

4. Verify: **Organization Settings → Agent Pools → aci-cicd-pool → Agents**
   - A placeholder agent should appear (shows "Offline" when idle — this is expected with KEDA scale-to-zero)

---

## Step 5 — Deploy Hub

The hub pipeline runs on the newly available self-hosted agents.

In ADO: **Pipelines → hub-deploy → Run pipeline**

```
useSelfHosted: true   ← default; uses aci-cicd-pool
```

This deploys:
- Hub VNet with Azure Firewall, Bastion, DNS Resolver
- Log Analytics Workspace
- Private DNS Zones (linked to hub VNet)
- Spoke Resource Group + VNet (`hub_managed = true` pattern)
- Bidirectional hub ↔ spoke VNet peering

After deployment, capture the hub outputs for CI/CD Day 2 integration:
```bash
cd infra/terraform/hub
terraform output -json
```

---

## Step 6 — CI/CD Day 2 Integration

After the hub is deployed, populate the `hub_*` variables in `infra/terraform/cicd/prod.tfvars`:

```hcl
hub_vnet_id              = "<hub VNet resource ID from hub output>"
hub_dns_resolver_ip      = "<DNS resolver inbound IP from hub output>"
hub_acr_dns_zone_id      = "<privatelink.azurecr.io zone ID from hub output>"
hub_blob_dns_zone_id     = "<privatelink.blob.core.windows.net zone ID from hub output>"
hub_vault_dns_zone_id    = "<privatelink.vaultcore.azure.net zone ID from hub output>"
hub_log_analytics_workspace_id = "<Log Analytics workspace ID from hub output>"
spoke_vnet_ids           = { "spoke-aks-prod" = "<spoke VNet ID from hub output>" }
```

> ⚠️ **IMPORTANT**: Day 2 changes modify the CI/CD VNet DNS and DNS zones, which **recreates the Container App Environment**. Run this pipeline on **Microsoft-hosted agents** to avoid the self-hosted agents self-destructing mid-pipeline.

In ADO: **Pipelines → cicd-deploy → Run pipeline**

```
useSelfHosted: false   ← required for Day 2
```

This adds:
- VNet peering: CI/CD ↔ Hub (bidirectional)
- VNet peering: CI/CD ↔ Spoke (required — peering is NOT transitive through hub)
- Switches to hub-owned private DNS zones
- Adds private endpoint to hub+spoke state storage account

---

## Step 7 — Deploy Spoke (AKS)

The spoke pipeline requires self-hosted agents — the private AKS API server is only reachable from the CI/CD VNet (via direct CI/CD ↔ Spoke peering added in Step 6).

In ADO: **Pipelines → spoke-deploy → Run pipeline**

This deploys:
- AKS private cluster (CNI Overlay + Cilium, BYOD private DNS)
- Control plane and kubelet managed identities + RBAC
- Route table (UDR → hub firewall), NSG
- Azure Container Registry (Premium, private endpoint)
- Azure Key Vault (Standard, private endpoint, purge protection)
- Spoke-specific firewall rule collection group (priority 500+)
- AKS diagnostic settings → hub Log Analytics
- **PostDeploy stage** (automatic): applies `NginxIngressController` Kubernetes manifest via `kubectl`, waits for internal load balancer IP assignment

---

## Post-Deploy Validation

```bash
# 1. Verify AKS cluster is running
az aks show \
  --name <aks-cluster-name> \
  --resource-group <spoke-rg> \
  --query "provisioningState" -o tsv
# Expected: Succeeded

# 2. Get credentials (from jump box VM or peered network)
az aks get-credentials \
  --name <aks-cluster-name> \
  --resource-group <spoke-rg>

# 3. Verify nodes are ready
kubectl get nodes

# 4. Verify NGINX internal load balancer
kubectl get svc -n app-routing-system
# Should show: nginx-internal-<hash>   LoadBalancer   <internal-IP>

# 5. Verify DNS resolution (run from jump box in management subnet)
nslookup <aks-private-fqdn>             # Should resolve to private IP
nslookup <acr-login-server>             # Should resolve to private IP
nslookup <kv-name>.vault.azure.net      # Should resolve to private IP
```

Run `scripts/validate-networking.sh` for a comprehensive networking validation from the jump box.

---

## Architecture Reference

See [ARCHITECTURE.md](./ARCHITECTURE.md) for a full description of all three landing zones, cross-cutting flows, DNS resolution chain, egress path, and design decisions. This file is formatted for import into [Eraser.io](https://eraser.io) to auto-generate architecture diagrams.
