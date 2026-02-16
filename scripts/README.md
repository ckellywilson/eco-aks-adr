# Scripts

This directory contains setup and validation scripts for the AKS landing zone.

## Scripts

### setup-ado-pipeline.sh

Automates the one-time setup of Azure DevOps pipelines for Terraform deployments using Workload Identity Federation (OIDC). Supports both **GitHub** and **ADO Git** repositories (auto-detected from `git remote`).

**What it does:**
1. Creates an Azure AD App Registration + Service Principal
2. Grants RBAC roles (Contributor + Storage Blob Data Contributor, plus User Access Administrator for spoke)
3. Creates an ADO service connection (Workload Identity Federation)
4. Creates a federated credential on the App Registration
5. Grants all pipelines access to the service connection
6. Creates the pipeline definition (GitHub or ADO Git)
7. Creates platform RG + management Key Vault + SSH key pair
8. Sets the agent pool and pipeline variables (`PLATFORM_KV_ID`)

**Usage:**
```bash
export AZURE_DEVOPS_PAT='<your-pat>'
./scripts/setup-ado-pipeline.sh
```

The script is **idempotent** — safe to re-run. It auto-detects the repository type from `git remote get-url origin` (`github.com` → GitHub, `dev.azure.com` → ADO Git).

**Prerequisites:**
- Azure CLI authenticated (`az login`)
- ADO PAT with Build (Read & Execute), Code (Read) scopes
- `jq`, `ssh-keygen`, `curl` installed
- For GitHub repos: GitHub service connection in ADO project

---

### validate-networking.sh

Unified validation script for hub and spoke infrastructure, DNS resolution, AKS connectivity, and in-cluster networking.

**Usage:**
```bash
./validate-networking.sh <environment> [--mode=infra|full]
```

**Modes:**

| Mode | Sections | Runner | Use Case |
|------|----------|--------|----------|
| `--mode=infra` | 1-3 (pre-flight, hub, spoke) | Pipeline agent | Post-apply validation in CI/CD |
| `--mode=full` | All 1-7 | Jump box via Bastion | Complete validation including DNS and AKS |

**What it checks:**

| Section | Description | Mode |
|---------|-------------|------|
| 1. Pre-flight | az, jq, kubectl availability, Azure login | Both |
| 2. Hub Infrastructure | RG, VNet, Firewall, DNS Resolver, DNS zones, Log Analytics | Both |
| 3. Spoke Infrastructure | RG, VNet, DNS config, peering, AKS config, ACR, KV | Both |
| 4. DNS Resolution | nslookup for AKS API, ACR, KV private endpoints | Full only |
| 5. AKS Connectivity | kubectl get nodes, node readiness | Full only |
| 6. In-Cluster Tests | External/Azure/K8s DNS, outbound HTTPS, pod overlay CIDR | Full only |
| 7. Summary | Pass/fail/warning counts | Both |

**Examples:**
```bash
# Pipeline post-apply validation (safe for external agents)
./validate-networking.sh prod --mode=infra

# Complete validation from jump box
./validate-networking.sh prod --mode=full

# Defaults to full mode
./validate-networking.sh prod
```

---

## Pipeline Integration

Both hub and spoke pipelines include automatic infra validation after apply:

```yaml
# Automatic in pipeline (post-apply step)
- script: |
    chmod +x scripts/validate-networking.sh
    ./scripts/validate-networking.sh prod --mode=infra
  displayName: 'Validate Infrastructure'
```

The pipeline also prints instructions for manual full validation from the jump box.

### Manual Validation (from jump box via Bastion)

For private AKS clusters, full DNS and connectivity validation must run from within the private network:

```bash
# Connect to spoke jump box via Azure Bastion
az network bastion ssh \
  --name <bastion-name> \
  --resource-group <hub-rg> \
  --target-resource-id <jumpbox-vm-id> \
  --auth-type ssh-key \
  --username azureuser \
  --ssh-key ~/.ssh/id_ed25519

# Run full validation
./scripts/validate-networking.sh prod --mode=full
```

---

## Self-Hosted CI/CD Agents

After deploying with `deploy_cicd_agents = true` in the hub, ACI-based pipeline agents run in the hub VNet. These agents can access all private resources across peered spokes.

### Post-Deploy Setup (Manual)

1. **Register UAMI in ADO**: Add the ACI agent UAMI as a service principal in your ADO organization
2. **Grant pool access**: Give the UAMI Admin access on the agent pool
3. **Switch pipeline pool**: Update pipeline YAML from `vmImage: 'ubuntu-latest'` to the self-hosted pool name

---

## Troubleshooting

### DNS Issues
- Check spoke VNet DNS servers: `az network vnet show -g <rg> -n <vnet> --query dhcpOptions.dnsServers`
- Verify DNS Resolver inbound endpoint IP matches spoke VNet custom DNS
- Check Private DNS zone VNet links to hub VNet

### Connectivity Issues
- Verify Azure Firewall rules allow required traffic
- Check route table on AKS subnet (default route via firewall)
- Ensure NSG rules don't block outbound traffic

### AKS Access Issues
- For private clusters, connect via jump box or VPN
- Verify VNet peering is in `Connected` state
- Check AKS API server authorized IP ranges

### Pod Networking Issues
- Verify Cilium dataplane is active: `kubectl get pods -n kube-system | grep cilium`
- Check network policies: `kubectl get networkpolicies -A`
- Validate pod CIDR is `192.168.0.0/16`

---

## Support

- Review [main README](../README.md)
- Check Terraform outputs: `terraform output`
- Review Azure Portal for resource status
- Check diagnostic logs in Log Analytics
