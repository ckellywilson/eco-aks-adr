# Validation Scripts

This directory contains validation scripts for testing the AKS landing zone deployment.

## Scripts

### 1. validate-deployment.sh

Validates that hub and spoke infrastructure is correctly deployed.

**Usage:**
```bash
./validate-deployment.sh <environment>
```

**Example:**
```bash
./validate-deployment.sh dev
```

**What it checks:**
- **Hub Infrastructure:**
  - Resource group existence
  - Hub VNet and address space
  - Azure Firewall and private IP
  - DNS Resolver (inbound/outbound endpoints)
  - Private DNS zones and VNet links
  - Log Analytics Workspace
  - Hub jump box VM

- **Spoke Infrastructure:**
  - Resource group existence
  - Spoke VNet and DNS configuration
  - VNet peering state
  - AKS cluster configuration
    - Kubernetes version
    - Network profile (Azure CNI Overlay, Cilium)
    - Private cluster status
    - Node pools
  - Azure Container Registry (ACR)
    - SKU (Premium)
    - Private endpoint
  - Key Vault
    - Private endpoint
  - Spoke jump box VM

- **AKS Connectivity:**
  - kubectl credentials retrieval
  - Node status
  - Cluster accessibility

**Prerequisites:**
- Azure CLI (`az`) installed and logged in
- `jq` installed for JSON parsing
- Appropriate Azure permissions to read resources

**Exit codes:**
- `0` - All checks passed
- `1` - One or more checks failed

---

### 2. validate-networking.sh

Validates network connectivity and DNS resolution from within the AKS cluster.

**Usage:**
```bash
./validate-networking.sh
```

**What it checks:**
- **DNS Resolution:**
  - External DNS (www.microsoft.com)
  - Azure service DNS (management.azure.com)
  - Kubernetes internal DNS (cluster.local)

- **Network Connectivity:**
  - Outbound HTTPS to internet
  - Azure API connectivity
  - Microsoft Container Registry (MCR) access

- **Pod Networking:**
  - Pod IP assignment
  - Overlay CIDR validation (192.168.0.0/16)
  - Node IP information

**Prerequisites:**
- `kubectl` configured with AKS cluster access
- AKS cluster running and accessible
- Permissions to create pods in a test namespace

**How it works:**
1. Creates a temporary `network-test` namespace
2. Deploys a pod with network diagnostic tools (`nicolaka/netshoot`)
3. Executes tests from within the pod
4. Cleans up test resources

**Exit codes:**
- `0` - All network tests passed
- `1` - One or more tests failed

---

## Running Validations

### After Hub Deployment

```bash
# Validate hub infrastructure
./validate-deployment.sh dev

# Check specific components
az network firewall show -g rg-hub-eus2-dev -n <firewall-name>
az dns-resolver list -g rg-hub-eus2-dev
```

### After Spoke Deployment

```bash
# Validate spoke infrastructure
./validate-deployment.sh dev

# Get AKS credentials
az aks get-credentials -g rg-spoke-aks-eus2-dev -n <aks-cluster-name>

# Validate networking from within cluster
./validate-networking.sh

# Check AKS node status
kubectl get nodes
kubectl get pods -A
```

### From Jump Box

For private AKS clusters, run validations from the spoke jump box:

```bash
# SSH to spoke jump box (via hub jump box or Bastion)
ssh azureuser@<jumpbox-ip>

# Clone repo or copy scripts
# Run validations
./validate-networking.sh
```

---

## Troubleshooting

### DNS Issues

If DNS resolution fails:
- Check spoke VNet DNS servers: `az network vnet show -g <rg> -n <vnet> --query dhcpOptions.dnsServers`
- Verify DNS Resolver inbound endpoint is `10.0.6.4`
- Check Private DNS zone VNet links

### Connectivity Issues

If outbound connectivity fails:
- Verify Azure Firewall rules allow required traffic
- Check route table on AKS subnet (default route via firewall)
- Ensure NSG rules don't block outbound traffic

### AKS Access Issues

If kubectl cannot connect:
- For private clusters, connect via jump box or VPN
- Verify VNet peering is in `Connected` state
- Check AKS API server authorized IP ranges

### Pod Networking Issues

If pods can't reach services:
- Verify Cilium dataplane is active: `kubectl get pods -n kube-system | grep cilium`
- Check network policies: `kubectl get networkpolicies -A`
- Validate pod CIDR is `192.168.0.0/16`

---

## Integration with CI/CD

These scripts can be integrated into CI/CD pipelines for automated validation:

### Azure DevOps

```yaml
- task: AzureCLI@2
  inputs:
    azureSubscription: 'your-service-connection'
    scriptType: 'bash'
    scriptLocation: 'scriptPath'
    scriptPath: './scripts/validate-deployment.sh'
    arguments: 'dev'
  displayName: 'Validate Deployment'
```

### GitHub Actions

```yaml
- name: Validate Deployment
  run: |
    chmod +x ./scripts/validate-deployment.sh
    ./scripts/validate-deployment.sh dev
  env:
    ARM_CLIENT_ID: ${{ secrets.ARM_CLIENT_ID }}
    ARM_CLIENT_SECRET: ${{ secrets.ARM_CLIENT_SECRET }}
    ARM_SUBSCRIPTION_ID: ${{ secrets.ARM_SUBSCRIPTION_ID }}
    ARM_TENANT_ID: ${{ secrets.ARM_TENANT_ID }}
```

---

## Additional Validation Steps

### Manual Validation Checklist

- [ ] Hub VNet peered to spoke VNet (bidirectional, state = Connected)
- [ ] Spoke VNet DNS servers = 10.0.6.4 (hub DNS Resolver)
- [ ] Private DNS zones linked to hub VNet
- [ ] Azure Firewall has rules for AKS dependencies
- [ ] AKS network profile: Azure CNI Overlay + Cilium
- [ ] ACR and Key Vault have private endpoints
- [ ] Diagnostic settings send logs to Log Analytics
- [ ] Jump boxes can SSH and have tools installed

### Load Testing

After validation, test AKS workloads:

```bash
# Deploy sample application
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80

# Scale and test
kubectl scale deployment nginx --replicas=10
kubectl get pods -o wide
```

---

## Support

For issues or questions:
- Review [main README](../README.md)
- Check Terraform outputs: `terraform output`
- Review Azure Portal for resource status
- Check diagnostic logs in Log Analytics
