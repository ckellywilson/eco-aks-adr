# AKS Spoke Infrastructure - Azure Kubernetes Service Cluster

This directory contains Terraform code for the AKS spoke infrastructure. The spoke hosts a production AKS cluster with private networking, Cilium CNI with overlay mode, and integration with the hub for centralized networking and monitoring.

## Architecture

The spoke includes:
- **VNet**: Private spoke virtual network (10.1.0.0/16)
  - AKS Node Pools subnet: 10.1.0.0/22
  - AKS System subnet: 10.1.4.0/24
  - Management subnet: 10.1.5.0/24

- **AKS Cluster**: Private cluster with:
  - Kubernetes 1.30
  - Azure CNI with Cilium overlay mode (192.168.0.0/16 pod CIDR)
  - System and user node pools (D4s_v3 VMs, 2 nodes each)
  - User-assigned managed identities
  - Workload Identity enabled for pod-to-Azure authentication
  - Azure Policy add-on enabled
  - Container Insights monitoring

- **Networking**:
  - User-defined routes for 0.0.0.0/0 via hub firewall
  - Network security groups for pod-to-pod communication
  - VNet peering to hub for firewall and DNS resolution

- **Security**:
  - Private API endpoint (no public access)
  - Managed identities for kubelet and control plane
  - Workload Identity for pod authentication
  - Network policies enforced by Cilium

- **Monitoring**:
  - Container Insights integration with hub Log Analytics workspace
  - 30-day log retention

## Prerequisites

### Before Deployment

1. **Hub Infrastructure** must be deployed first:
   ```bash
   cd ../hub
   ./deploy.sh dev  # or prod
   cd ../spoke-aks-prod
   ```

2. **Hub Outputs**: Hub deployment generates `hub-outputs.json` which spoke consumes for:
   - Hub VNet ID (for peering)
   - Firewall private IP (for UDR)
   - Log Analytics workspace ID (for monitoring)

3. **Requirements**:
   - Terraform >= 1.9
   - Azure CLI >= 2.50
   - Appropriate Azure subscription permissions
   - kubectl installed for cluster access

## Deployment Order

**Important**: Hubs must be deployed before spokes.

### Step 1: Deploy Hub Infrastructure

```bash
cd ../hub
terraform init -backend-config="backend-dev.tfbackend"
terraform plan -var-file="dev.tfvars"
terraform apply
cd ../spoke-aks-prod
```

### Step 2: Deploy Spoke Infrastructure

```bash
# Initialize spoke with backend config
terraform init -backend-config="backend-dev.tfbackend"

# Plan deployment (reads hub outputs)
terraform plan -var-file="dev.tfvars"

# Apply deployment
terraform apply

# Generate outputs
terraform output -json > spoke-aks-prod-outputs.json
```

### Using Deploy Script

```bash
# Ensure hub is deployed first, then:
./deploy.sh dev   # Deploy to dev
./deploy.sh prod  # Deploy to prod
```

## Hub-Spoke Integration

### Hub Outputs Consumption

The spoke reads hub outputs from `../hub/hub-outputs.json`:

```hcl
locals {
  hub_outputs = jsondecode(file("../hub/hub-outputs.json"))
}
```

**Hub outputs used by spoke:**
- `hub_vnet_id`: For VNet peering
- `firewall_private_ip`: For default route (0.0.0.0/0)
- `log_analytics_workspace_id`: For Container Insights
- `private_dns_zone_ids`: For private endpoint resolution

### If Hub Outputs Not Available

If hub outputs file is not found, the spoke falls back to data sources:

```hcl
data "azurerm_virtual_network" "hub" {
  name                = "vnet-hub-${var.environment}-${local.location_code}"
  resource_group_name = var.hub_resource_group_name
}
```

## Accessing Your Cluster

After deployment:

```bash
# Get credentials (requires Azure CLI authenticated)
az account set --subscription f8a5f387-2f0b-42f5-b71f-5ee02b8967cf
az aks get-credentials \
  --resource-group rg-aks-eus2-prod \
  --name aks-eco-prod-eus2

# Verify cluster access
kubectl cluster-info
kubectl get nodes
```

## Configuration

### AKS Cluster Configuration

Configured via Terraform variables:

- **kubernetes_version**: 1.30 (latest stable)
- **aks_sku_tier**: Standard (not Free)
- **network_plugin**: azure (CNI)
- **network_policy**: cilium (for overlay mode)
- **pod_cidr**: 192.168.0.0/16
- **service_cidr**: 172.16.0.0/16
- **private_cluster_enabled**: true (no public API endpoint)
- **enable_workload_identity**: true (for pod authentication)
- **enable_azure_policy**: true (governance)

### Node Pool Configuration

**System Pool:**
- VM Size: D4s_v3 (4 vCPU, 16 GB RAM)
- Node Count: 2
- Auto-scaling: Disabled
- Labels: system

**User Pool:**
- VM Size: D4s_v3 (4 vCPU, 16 GB RAM)
- Node Count: 2
- Auto-scaling: Disabled
- Labels: workload=user

### Egress Configuration

All outbound traffic routes through hub firewall:

```
AKS pods → 0.0.0.0/0 → UDR (10.0.1.4 - Hub Firewall) → Internet/Azure
```

This provides:
- Centralized egress filtering via hub firewall
- IP whitelist for APIs and external services
- Logging and monitoring of all egress traffic

## Monitoring & Logging

### Container Insights Integration

Cluster sends diagnostic data to hub Log Analytics workspace:

```bash
# View cluster logs
kubectl logs -n kube-system -l app=coredns

# View metrics in Azure Portal
# Monitor → Container Insights → Cluster name
```

### Log Sources

- Kubelet logs
- API server logs
- Controller manager logs
- Scheduler logs
- Pod logs (30-day retention)

## Workload Identity Setup

Pods can authenticate to Azure services without secrets using Workload Identity:

### Example: Pod Accessing Key Vault

1. **Create federated identity credential** (after deployment):
```bash
az identity federated-credential create \
  --identity-name uami-aks-kubelet-prod-eus2 \
  --resource-group rg-aks-eus2-prod \
  --issuer $(terraform output -raw aks_oidc_issuer_url) \
  --subject system:serviceaccount:my-namespace:my-sa \
  --audiences api://AzureADTokenExchange
```

2. **Pod deployment with Workload Identity**:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-sa
  namespace: my-namespace
  annotations:
    azure.workload.identity/client-id: <kubelet-identity-client-id>
---
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
  namespace: my-namespace
spec:
  serviceAccountName: my-sa
  containers:
  - name: my-container
    image: my-image:latest
  nodeSelector:
    kubernetes.io/os: linux
```

## NGINX Ingress Controller (Internal Load Balancer)

### Overview

The AKS cluster includes the Azure-managed NGINX ingress controller (Web App Routing add-on) configured with an internal load balancer for Layer 7 routing of workloads within the private network.

**Architecture:**
```
Internal Traffic Flow:
Hub/Spoke Network Clients → Internal LB (10.1.0.50) → NGINX Pods → AKS Workloads
                              ↓
                         Cilium Network Policy
                              ↓
                         Azure CNI Overlay

Future with App Gateway:
Internet → App Gateway (WAF) → Internal NGINX (10.1.0.50) → AKS Workloads
         [10.0.5.x in hub]    [spoke]
         Public Layer 7        Internal routing
```

### What's Configured in Terraform

✅ **Automatically configured:**
- Web App Routing add-on enabled on AKS cluster
- NSG rules allowing HTTP/HTTPS (80/443) from hub and spoke VNets to 10.1.0.50
- Static IP reservation (10.1.0.50) from AKS nodes subnet (10.1.0.0/22)

⚠️ **Requires post-deployment configuration:**
- Kubernetes `NginxIngressController` custom resource (see below)
- Application Ingress resources
- (Optional) TLS certificates via Key Vault

### Post-Deployment Configuration

After Terraform applies successfully, configure the internal NGINX controller:

#### Step 1: Create Internal NGINX Controller

manifest: `manifests/nginx-internal-controller.yaml`

```bash
# Get cluster credentials
az aks get-credentials \
  --resource-group rg-aks-eus2-prod \
  --name aks-eco-prod-eus2

# Apply the NGINX controller configuration
kubectl apply -f manifests/nginx-internal-controller.yaml

# Verify controller creation (may take 1-2 minutes)
kubectl get nginxingresscontroller
```

Expected output:
```
NAME             INGRESSCLASS      CONTROLLERNAMEPREFIX   AVAILABLE
default          webapprouting...  nginx                  True
nginx-internal   nginx-internal    nginx-internal         True
```

#### Step 2: Verify Internal Load Balancer

```bash
# Check the NGINX controller service
kubectl get svc -n app-routing-system

# Verify internal LB IP (should be 10.1.0.50)
kubectl get svc -n app-routing-system \
  -l app.kubernetes.io/instance=nginx-internal \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}'
```

#### Step 3: Deploy Sample Application (Optional)

Use the provided example:

```bash
# Deploy sample app with ingress
kubectl apply -f manifests/example-ingress.yaml

# Verify deployment
kubectl get pods,svc,ingress
```

#### Step 4: Test from Jump Box or Hub VNet

```bash
# SSH to jump box (from Bastion or hub network)
# Test HTTP access
curl http://10.1.0.50/hello

# Test with host header
curl -H "Host: myapp.internal" http://10.1.0.50/
```

### Configuration Options

#### Static IP vs Dynamic

The static IP `10.1.0.50` is configured via `nginx_internal_lb_ip` variable. To change:

```hcl
# In tfvars
nginx_internal_lb_ip = "10.1.0.60"  # Must be in 10.1.0.0/22 range
```

Then reapply Terraform and update the NginxIngressController manifest.

#### DNS Integration (Optional)

DNS integration is not configured by this Terraform module. To use DNS names for applications exposed via the internal Nginx ingress:

- Create or use an existing **Azure Private DNS Zone** and link it to both the hub and spoke VNets.
- Create **A records** in that zone pointing to the internal load balancer IP (`nginx_internal_lb_ip`, default `10.1.0.50`).
- Update your application ingress resources to use hostnames that match the DNS records you created.

This keeps DNS management separate from the cluster deployment and avoids implicit dependencies in this initial implementation.

### Common Issues

**Controller not available:**
- Check add-on enabled: `az aks show -n aks-eco-prod-eus2 -g rg-aks-eus2-prod --query 'ingressProfile.webAppRouting.enabled'`
- Check pods: `kubectl get pods -n app-routing-system`

**Cannot reach internal LB IP:**
- Verify you're testing from hub/spoke network (not internet)
- Check NSG rules allow traffic: `az network nsg rule list -g rg-aks-eus2-prod --nsg-name nsg-aks-nodes-eus2-prod`
- Verify firewall rules if testing from hub

**502 Bad Gateway:**
- Check backend pods are running: `kubectl get pods`
- Check service endpoints: `kubectl get endpoints`
- Check ingress backend configuration

**Certificate issues:**
- Secrets Store CSI driver not installed by default
- Add `addon_profile_azure_keyvault_secrets_provider` to enable
- Or use cert-manager for Let's Encrypt

### Example Ingress Manifest

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx-internal  # Use internal controller
  rules:
  - host: myapp.internal.contoso.com
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 8080
      - path: /web
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
```

### Monitor NGINX Controller

```bash
# View controller logs
kubectl logs -n app-routing-system \
  -l app.kubernetes.io/component=controller \
  -l app.kubernetes.io/instance=nginx-internal

# Watch ingress events
kubectl get events -n default --field-selector involvedObject.kind=Ingress

# Check Container Insights
# Azure Portal → AKS Cluster → Monitoring → Container Insights → Workloads
```

### Best Practices

1. **Use path-based routing** - Multiple apps behind single LB IP
2. **Enable TLS** - Even for internal traffic (production)
3. **Set resource limits** - On NGINX controller pods (see manifest example)
4. **Use Cilium network policies** - Restrict traffic to NGINX ingress pods
5. **Monitor ingress metrics** - Via Container Insights or Prometheus

### References

- [Web App Routing Add-on](https://learn.microsoft.com/en-us/azure/aks/app-routing)
- [NGINX Configuration](https://learn.microsoft.com/en-us/azure/aks/app-routing-nginx-configuration)
- [Internal NGINX Controller](https://learn.microsoft.com/en-us/azure/aks/create-nginx-ingress-private-controller)
- [NginxIngressController CRD](https://aka.ms/aks/approuting/nginxingresscontrollercrd)

## Networking Details

### Subnets

| Subnet | CIDR | Purpose |
|--------|------|---------|
| AKS Nodes | 10.1.0.0/22 | Pod CIDR range |
| AKS System | 10.1.4.0/24 | System components |
| Management | 10.1.5.0/24 | VM/Bastion access |

### NSGs

**AKS Nodes NSG:**
- Allows: Intra-subnet traffic (pod-to-pod)
- Denies: All other inbound (pods filtered by network policy)

### Routing

**Route Table (rt-spoke-prod-eus2):**
- 0.0.0.0/0 → 10.0.1.4 (Hub Firewall IP)

This UDR forces all traffic through the hub firewall for:
- Central logging
- Egress filtering
- Compliance monitoring

## Common Operations

### Scaling Node Pool

```bash
# Get current nodes
kubectl get nodes

# Update in tfvars and redeploy
terraform apply -var-file="prod.tfvars"
```

### Upgrading Kubernetes

```bash
# Update kubernetes_version in tfvars
terraform apply -var-file="prod.tfvars"
```

### Adding User Node Pool

```hcl
# In main.tf, add to node_pools
node_pools = {
  user = { /* existing config */ }
  workload = {
    name                = "workload"
    vm_size             = "Standard_D8s_v3"
    node_count          = 3
    node_labels = { workload = "heavy" }
  }
}
```

## Troubleshooting

### Cannot connect to cluster

```bash
# Verify cluster is private
terraform output aks_private_fqdn

# Verify you're connected via hub/bastion
# Private clusters require:
# 1. Private endpoint connectivity
# 2. Bastion or VPN to hub
# 3. DNS resolution via hub private DNS zones
```

### Pods cannot access hub resources

```bash
# Check network policy
kubectl get networkpolicies -A

# Check UDR
az network route-table route list \
  --resource-group rg-aks-eus2-prod \
  --route-table-name rt-spoke-prod-eus2

# Check firewall rules
# Firewall must allow AKS → Hub services
```

### Container Insights not showing data

```bash
# Verify workspace is linked
terraform output log_analytics_workspace_id

# Check diagnostics are enabled
kubectl get deploy -n kube-system | grep omsagent
```

## Cost Estimation

Monthly costs for default configuration:

| Component | Cost |
|-----------|------|
| AKS Cluster (Standard tier) | ~$73 |
| 4 D4s_v3 VMs (2 system + 2 user) | ~$600 |
| Managed Disks (100 GB) | ~$5 |
| Log Analytics | ~$50 (variable) |
| Private DNS resolution | ~$5 |
| **Total** | **~$730** |

## Next Steps

1. Deploy hub infrastructure first
2. Deploy spoke AKS cluster
3. Configure workload identity for pods
4. Deploy applications
5. Configure ingress (via hub Application Gateway)
6. Set up CI/CD pipeline for workload deployment

## Support

- **AKS Troubleshooting**: https://learn.microsoft.com/en-us/azure/aks/troubleshooting
- **Cilium Documentation**: https://docs.cilium.io/
- **Workload Identity**: https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview
- **Azure Verified Modules**: https://registry.terraform.io/search/modules?namespace=Azure

## NGINX Ingress Controller (Internal Load Balancer)

### Overview

The AKS cluster is configured with the Azure-managed NGINX ingress controller (Web App Routing add-on) that uses an internal load balancer for Layer 7 routing of workloads within the private network.

**Architecture:**
```
Internal Traffic Flow:
Hub/Spoke Network Clients → Internal LB (10.1.0.50) → NGINX Ingress → AKS Workloads
                              ↓
                         Cilium Network Policy
                              ↓
                         Azure CNI Overlay
```

**Future Architecture with App Gateway:**
```
Internet Traffic Flow:
Internet → App Gateway (WAF) → Internal NGINX (10.1.0.50) → AKS Workloads
         [10.0.5.x in hub]    [10.1.0.50 in spoke]
         Public-facing         Internal routing
         Layer 7 WAF          Layer 7 path/host routing
```

### Configuration Details

**Web App Routing Add-on:**
- **Enabled**: `var.enable_web_app_routing = true`
- **Internal LB IP**: `10.1.0.50` (static IP from AKS nodes subnet)
- **Subnet**: 10.1.0.0/22 (AKS nodes subnet)
- **DNS Integration**: None by default (optional Azure DNS zone)
- **TLS**: Not configured by default (can add via Key Vault CSI)

**NSG Rules:**
The AKS nodes NSG includes rules allowing HTTP/HTTPS traffic:
- **Ports**: 80, 443
- **Source**: Hub VNet (10.0.0.0/16) and Spoke VNet (10.1.0.0/16)
- **Destination**: NGINX internal LB IP (10.1.0.50)

### Post-Deployment Configuration

After Terraform deployment, you must create a Kubernetes `NginxIngressController` resource to configure the internal load balancer:

**Step 1: Create NGINX Ingress Controller with Internal LB**

Save this manifest as `nginx-internal-controller.yaml`:

```yaml
apiVersion: approuting.kubernetes.azure.com/v1alpha1
kind: NginxIngressController
metadata:
  name: nginx-internal
spec:
  ingressClassName: nginx-internal
  controllerNamePrefix: nginx-internal
  loadBalancerAnnotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
    service.beta.kubernetes.io/azure-load-balancer-internal-subnet: "aks-nodes"
```

Apply the configuration:

```bash
# Get cluster credentials
az aks get-credentials \
  --resource-group rg-aks-eus2-prod \
  --name aks-eco-prod-eus2

# Create the internal NGINX controller
kubectl apply -f nginx-internal-controller.yaml

# Verify the controller was created
kubectl get nginxingresscontroller -A

# Wait for the internal load balancer to be provisioned
kubectl get svc -n app-routing-system

# Get the internal LB IP (should be 10.1.0.50)
kubectl get svc -n app-routing-system -l app.kubernetes.io/name=nginx -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}'
```

**Step 2: Create an Ingress Resource**

Example ingress for a sample application:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  namespace: default
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx-internal
  rules:
  - host: myapp.internal
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp-service
            port:
              number: 80
```

**Step 3: Test Connectivity**

From the jump box or any VM in the hub/spoke network:

```bash
# Test HTTP access to internal LB
curl -H "Host: myapp.internal" http://10.1.0.50/

# Or if DNS is configured
curl http://myapp.internal/
```

### Monitoring

```bash
# View NGINX controller logs
kubectl logs -n app-routing-system -l app.kubernetes.io/name=nginx

# View ingress controller status
kubectl get nginxingresscontroller nginx-internal -o yaml

# View all ingress resources
kubectl get ingress -A
```

This section is a quick-start operational summary. For complete documentation including DNS configuration, TLS setup, and troubleshooting, see the **NGINX Ingress Controller (Internal Load Balancer)** section earlier in this README.

## Firewall Rules

### Spoke Firewall Rule Collection Group

The spoke deployment creates its own firewall rule collection group on the hub's firewall policy at priority 500+ (hub baseline rules use priority 100-499). This enables spoke-specific egress rules without modifying hub infrastructure.

**Automatically configured:**
- **Ubuntu package repositories** - Allows apt/dpkg access for jump box and Ubuntu-based workloads
  - security.ubuntu.com
  - archive.ubuntu.com
  - packages.ubuntu.com
  - *.archive.ubuntu.com
- **Placeholder application rule collection** - Ready for custom application FQDNs

**Adding custom application rules:**

Edit `main.tf` and add FQDNs to the `spoke-application-rules` collection:

```hcl
destination_fqdns = [
  "api.myapp.com",
  "cdn.myapp.com",
  "*.azurewebsites.net"
]
```

Then reapply Terraform:

```bash
terraform plan -var-file="prod.tfvars"
terraform apply
```

**View firewall rules:**

```bash
# List all rule collection groups on hub firewall policy
az network firewall policy rule-collection-group list \
  --policy-name afwpol-hub-prod-eus2 \
  --resource-group rg-hub-eus2-prod

# View spoke-specific rules
az network firewall policy rule-collection-group show \
  --name spoke-aks-prod \
  --policy-name afwpol-hub-prod-eus2 \
  --resource-group rg-hub-eus2-prod
```

**Monitoring firewall traffic:**

```bash
# View firewall logs in Log Analytics workspace
az monitor log-analytics query \
  --workspace <workspace-id> \
  --analytics-query "AzureDiagnostics | where Category == 'AzureFirewallApplicationRule' | where SourceIp startswith '10.1.' | top 100 by TimeGenerated desc"
```

### Best Practices

1. **Minimize FQDN lists** - Use Azure-managed FQDN tags where available (already configured for AKS via hub)
2. **Restrict source addresses** - Spoke rules use spoke VNet CIDR only (10.1.0.0/16)
3. **Priority management** - Keep spoke rules at 500+ to avoid conflicts with hub baseline
4. **Test before production** - Validate egress connectivity in dev environment first
5. **Monitor firewall logs** - Review blocked requests regularly to adjust rules

### Troubleshooting Egress Issues

**If workloads cannot reach external services:**

```bash
# Check if traffic is blocked by firewall
# SSH to jump box via Bastion
curl -v https://example.com

# View firewall logs for denials
az monitor log-analytics query \
  --workspace <workspace-id> \
  --analytics-query "AzureDiagnostics | where Category == 'AzureFirewallApplicationRule' | where Action_s == 'Deny' | where SourceIp startswith '10.1.'"
```

**Common causes:**
- FQDN not in allowed list (add to spoke-application-rules)
- Port mismatch (verify protocol/port in rule)
- Source address restriction (verify spoke CIDR in rule)

