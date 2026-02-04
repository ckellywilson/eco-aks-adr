# AKS Egress Restriction Demo Guide

This guide provides hands-on procedures to demonstrate and validate AKS egress restrictions using Azure Firewall in a hub-spoke architecture.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Demo Architecture](#demo-architecture)
4. [Part 1: Non-Restricted Baseline](#part-1-non-restricted-baseline)
5. [Part 2: Egress-Restricted Configuration](#part-2-egress-restricted-configuration)
6. [Part 3: Comparison and Validation](#part-3-comparison-and-validation)
7. [Part 4: Advanced Scenarios](#part-4-advanced-scenarios)
8. [Troubleshooting](#troubleshooting)
9. [Cleanup](#cleanup)

---

## Overview

This demo showcases the difference between:
- **Non-Restricted AKS**: Standard configuration with permissive egress
- **Egress-Restricted AKS**: All egress forced through Azure Firewall with deny-by-default policies

**Demonstrates:**
- ✅ Blocking unauthorized external access
- ✅ Allowing approved Azure services (ACR, Key Vault, SQL)
- ✅ Centralized logging and visibility
- ✅ Private endpoints bypass firewall (expected behavior)

**Target Audience:** SecOps teams, security architects, compliance officers, platform engineers

---

## Prerequisites

### Deployed Infrastructure
- ✅ Hub landing zone with Azure Firewall
- ✅ Log Analytics workspace
- ✅ Private DNS zones linked to hub VNet
- ✅ Two AKS spoke environments (or ability to toggle configuration)

### Required Tools
```bash
# Verify tools installed
az --version
kubectl version --client
curl --version
jq --version
```

### Required Permissions
- Contributor on spoke Resource Groups
- Network Contributor on hub VNet
- Log Analytics Reader for Firewall logs
- AKS cluster admin access

---

## Demo Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                         Hub VNet                             │
│  ┌────────────────────────────────────────────────────┐     │
│  │          Azure Firewall (10.0.1.4)                 │     │
│  │  Rules:                                            │     │
│  │  - Allow: AKS required endpoints                   │     │
│  │  - Allow: ACR, Key Vault, Azure SQL              │     │
│  │  - Deny: All other internet                        │     │
│  └────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────┘
                           │
                           │ Peering
                           │
┌──────────────────────────┼───────────────────────────────────┐
│                    Spoke VNet (10.1.0.0/16)                  │
│                          │                                    │
│  ┌───────────────────────▼──────────────────┐               │
│  │  AKS Cluster (Private)                   │               │
│  │  - Scenario A: Direct internet egress    │               │
│  │  - Scenario B: Force tunnel via FW       │               │
│  └──────────────────────────────────────────┘               │
│                                                               │
│  ┌──────────────────────────────────────────┐               │
│  │  Private Endpoints                       │               │
│  │  - ACR, Key Vault, Azure SQL            │               │
│  └──────────────────────────────────────────┘               │
└───────────────────────────────────────────────────────────────┘
```

### Test Targets

| Target | Type | Non-Restricted | Egress-Restricted (No Rule) | Egress-Restricted (With Rule) |
|--------|------|----------------|----------------------------|------------------------------|
| api.github.com | External API | ✅ Works | ❌ Blocked | ✅ Works (if allowed) |
| www.google.com | External Web | ✅ Works | ❌ Blocked | ❌ Blocked |
| ACR (Private Endpoint) | Azure PaaS | ✅ Works | ✅ Works (PE bypass) | ✅ Works (PE bypass) |
| Azure SQL (Private Endpoint) | Azure PaaS | ✅ Works | ✅ Works (PE bypass) | ✅ Works (PE bypass) |
| Azure SQL (Public Endpoint) | Azure PaaS | ✅ Works | ❌ Blocked | ✅ Works (if allowed) |
| mcr.microsoft.com | Container Registry | ✅ Works | ✅ Works (required rule) | ✅ Works (required rule) |

---

## Part 1: Non-Restricted Baseline

Deploy and test the baseline (standard security) configuration.

### Step 1: Deploy Non-Restricted AKS

```bash
cd /workspaces/aks-lz-ghcp/spoke-aks

# Create baseline configuration
cat > environments/demo-baseline.tfvars <<EOF
# Scenario 2: Platform-provided networking
create_resource_group  = false
create_virtual_network = false
create_vnet_peering   = false
create_route_table    = false

existing_resource_group_name       = "rg-spoke-aks-demo"
existing_virtual_network_name      = "vnet-spoke-aks-demo"
existing_aks_system_subnet_name    = "snet-aks-system"
existing_aks_user_subnet_name      = "snet-aks-user"
existing_private_endpoint_subnet_name = "snet-private-endpoints"

# Standard Security (Non-Restricted)
enable_egress_restriction = false
egress_security_level    = "standard"

# Hub references
hub_virtual_network_id     = "<hub-vnet-id>"
hub_firewall_private_ip    = "10.0.1.4"
log_analytics_workspace_id = "<log-analytics-id>"

# Naming
environment = "demo-baseline"
location    = "eastus"
EOF

# Deploy
terraform init
terraform plan -var-file=environments/demo-baseline.tfvars -out=baseline.tfplan
terraform apply baseline.tfplan
```

### Step 2: Connect to Baseline AKS

```bash
# Get credentials
az aks get-credentials \
  --resource-group rg-spoke-aks-demo \
  --name aks-demo-baseline \
  --overwrite-existing

# Verify connectivity
kubectl get nodes
kubectl get pods -A
```

### Step 3: Deploy Test Workload (Baseline)

```bash
# Create test namespace
kubectl create namespace egress-test

# Deploy test pod with network tools
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: egress-test-baseline
  namespace: egress-test
  labels:
    app: egress-test
spec:
  containers:
  - name: netshoot
    image: nicolaka/netshoot:latest
    command:
      - sleep
      - "infinity"
    resources:
      requests:
        memory: "64Mi"
        cpu: "100m"
      limits:
        memory: "128Mi"
        cpu: "200m"
EOF

# Wait for pod to be ready
kubectl wait --for=condition=ready pod/egress-test-baseline -n egress-test --timeout=120s
```

### Step 4: Test External Connectivity (Baseline)

```bash
# Test 1: External API (GitHub)
echo "=== Test 1: GitHub API ==="
kubectl exec -n egress-test egress-test-baseline -- curl -I -s -o /dev/null -w "%{http_code}\n" https://api.github.com
# Expected: 200 ✅

# Test 2: External Website (Google)
echo "=== Test 2: Google ==="
kubectl exec -n egress-test egress-test-baseline -- curl -I -s -o /dev/null -w "%{http_code}\n" https://www.google.com
# Expected: 200 or 301 ✅

# Test 3: External DNS resolution
echo "=== Test 3: DNS Resolution ==="
kubectl exec -n egress-test egress-test-baseline -- nslookup google.com
# Expected: Resolves to public IP ✅

# Test 4: Microsoft Container Registry
echo "=== Test 4: MCR ==="
kubectl exec -n egress-test egress-test-baseline -- curl -I -s -o /dev/null -w "%{http_code}\n" https://mcr.microsoft.com
# Expected: 200 ✅

# Test 5: Trace route to external
echo "=== Test 5: Traceroute ==="
kubectl exec -n egress-test egress-test-baseline -- traceroute -m 5 8.8.8.8
# Expected: Direct egress via Azure Load Balancer ✅
```

### Step 5: Document Baseline Results

```bash
# Capture baseline test results
cat > baseline-results.txt <<EOF
=== AKS Egress Baseline Test Results ===
Date: $(date)
Configuration: Non-Restricted (Standard Security)
AKS Outbound Type: loadBalancer

Test 1 - GitHub API: $(kubectl exec -n egress-test egress-test-baseline -- curl -I -s -o /dev/null -w "%{http_code}" https://api.github.com)
Test 2 - Google: $(kubectl exec -n egress-test egress-test-baseline -- curl -I -s -o /dev/null -w "%{http_code}" https://www.google.com)
Test 3 - MCR: $(kubectl exec -n egress-test egress-test-baseline -- curl -I -s -o /dev/null -w "%{http_code}" https://mcr.microsoft.com)

Conclusion: All external connectivity allowed ✅
EOF

cat baseline-results.txt
```

---

## Part 2: Egress-Restricted Configuration

Deploy and test the egress-restricted (strict security) configuration.

### Step 1: Configure Azure Firewall Rules

**Platform Team: Configure Firewall Application Rules**

```bash
# Set variables
FIREWALL_NAME="afw-hub"
FIREWALL_RG="rg-hub"
POLICY_NAME="afwp-hub"

# Get existing policy ID
POLICY_ID=$(az network firewall policy show \
  --name $POLICY_NAME \
  --resource-group $FIREWALL_RG \
  --query id -o tsv)

# Create rule collection group for AKS egress
az network firewall policy rule-collection-group create \
  --name "AKS-Egress-Rules" \
  --policy-name $POLICY_NAME \
  --resource-group $FIREWALL_RG \
  --priority 1000

# Add AKS required endpoints
az network firewall policy rule-collection-group collection add-filter-collection \
  --name "AKS-Required-FQDNs" \
  --policy-name $POLICY_NAME \
  --resource-group $FIREWALL_RG \
  --rule-collection-group-name "AKS-Egress-Rules" \
  --collection-priority 100 \
  --action Allow \
  --rule-name "AKS-ControlPlane" \
  --rule-type ApplicationRule \
  --source-addresses "10.1.0.0/16" \
  --protocols "Https=443" \
  --target-fqdns \
    "*.hcp.eastus.azmk8s.io" \
    "mcr.microsoft.com" \
    "*.data.mcr.microsoft.com" \
    "management.azure.com" \
    "login.microsoftonline.com" \
    "packages.microsoft.com" \
    "acs-mirror.azureedge.net"

# Add Azure services (ACR, Key Vault, Storage)
az network firewall policy rule-collection-group collection add-filter-collection \
  --name "Azure-PaaS-Services" \
  --policy-name $POLICY_NAME \
  --resource-group $FIREWALL_RG \
  --rule-collection-group-name "AKS-Egress-Rules" \
  --collection-priority 110 \
  --action Allow \
  --rule-name "Azure-Services" \
  --rule-type ApplicationRule \
  --source-addresses "10.1.0.0/16" \
  --protocols "Https=443" \
  --target-fqdns \
    "*.azurecr.io" \
    "*.blob.core.windows.net" \
    "*.vault.azure.net"

# Verify rules created
az network firewall policy rule-collection-group list \
  --policy-name $POLICY_NAME \
  --resource-group $FIREWALL_RG \
  --query "[].{Name:name, Priority:priority}" -o table
```

### Step 2: Deploy Egress-Restricted AKS

```bash
cd /workspaces/aks-lz-ghcp/spoke-aks

# Create egress-restricted configuration
cat > environments/demo-restricted.tfvars <<EOF
# Scenario 2: Platform-provided networking
create_resource_group  = false
create_virtual_network = false
create_vnet_peering   = false
create_route_table    = false

existing_resource_group_name       = "rg-spoke-aks-demo"
existing_virtual_network_name      = "vnet-spoke-aks-demo"
existing_aks_system_subnet_name    = "snet-aks-system"
existing_aks_user_subnet_name      = "snet-aks-user"
existing_private_endpoint_subnet_name = "snet-private-endpoints"

# Egress-Restricted Security (STRICT)
enable_egress_restriction = true
egress_security_level    = "strict"

# Hub references
hub_virtual_network_id     = "<hub-vnet-id>"
hub_firewall_private_ip    = "10.0.1.4"
log_analytics_workspace_id = "<log-analytics-id>"

# Naming
environment = "demo-restricted"
location    = "eastus"
EOF

# Deploy
terraform init
terraform plan -var-file=environments/demo-restricted.tfvars -out=restricted.tfplan
terraform apply restricted.tfplan
```

### Step 3: Connect to Restricted AKS

```bash
# Get credentials
az aks get-credentials \
  --resource-group rg-spoke-aks-demo \
  --name aks-demo-restricted \
  --overwrite-existing

# Verify connectivity
kubectl get nodes
kubectl get pods -A
```

### Step 4: Deploy Test Workload (Restricted)

```bash
# Create test namespace
kubectl create namespace egress-test

# Deploy test pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: egress-test-restricted
  namespace: egress-test
  labels:
    app: egress-test
spec:
  containers:
  - name: netshoot
    image: nicolaka/netshoot:latest
    command:
      - sleep
      - "infinity"
    resources:
      requests:
        memory: "64Mi"
        cpu: "100m"
      limits:
        memory: "128Mi"
        cpu: "200m"
EOF

# Wait for pod
kubectl wait --for=condition=ready pod/egress-test-restricted -n egress-test --timeout=120s
```

### Step 5: Test External Connectivity (Restricted)

```bash
# Test 1: External API (GitHub) - Should be BLOCKED
echo "=== Test 1: GitHub API (Should Fail) ==="
kubectl exec -n egress-test egress-test-restricted -- timeout 10 curl -I -s -o /dev/null -w "%{http_code}\n" https://api.github.com || echo "BLOCKED ❌"
# Expected: Timeout or connection refused ❌

# Test 2: External Website (Google) - Should be BLOCKED
echo "=== Test 2: Google (Should Fail) ==="
kubectl exec -n egress-test egress-test-restricted -- timeout 10 curl -I -s -o /dev/null -w "%{http_code}\n" https://www.google.com || echo "BLOCKED ❌"
# Expected: Timeout or connection refused ❌

# Test 3: MCR (Allowed by firewall rule) - Should WORK
echo "=== Test 3: MCR (Should Work) ==="
kubectl exec -n egress-test egress-test-restricted -- curl -I -s -o /dev/null -w "%{http_code}\n" https://mcr.microsoft.com
# Expected: 200 ✅

# Test 4: Azure Management API (Allowed) - Should WORK
echo "=== Test 4: Azure Management API (Should Work) ==="
kubectl exec -n egress-test egress-test-restricted -- curl -I -s -o /dev/null -w "%{http_code}\n" https://management.azure.com
# Expected: 401 (unauthorized but reachable) ✅

# Test 5: Verify routing through firewall
echo "=== Test 5: Check Route Table ==="
kubectl exec -n egress-test egress-test-restricted -- ip route
# Expected: Default route via 10.0.1.4 (Firewall) ✅
```

### Step 6: Document Restricted Results

```bash
# Capture restricted test results
cat > restricted-results.txt <<EOF
=== AKS Egress Restricted Test Results ===
Date: $(date)
Configuration: Egress-Restricted (Strict Security)
AKS Outbound Type: userDefinedRouting
Firewall: 10.0.1.4

Test 1 - GitHub API: $(kubectl exec -n egress-test egress-test-restricted -- timeout 10 curl -I -s -o /dev/null -w "%{http_code}" https://api.github.com 2>&1 || echo "BLOCKED")
Test 2 - Google: $(kubectl exec -n egress-test egress-test-restricted -- timeout 10 curl -I -s -o /dev/null -w "%{http_code}" https://www.google.com 2>&1 || echo "BLOCKED")
Test 3 - MCR: $(kubectl exec -n egress-test egress-test-restricted -- curl -I -s -o /dev/null -w "%{http_code}" https://mcr.microsoft.com)
Test 4 - Azure Mgmt: $(kubectl exec -n egress-test egress-test-restricted -- curl -I -s -o /dev/null -w "%{http_code}" https://management.azure.com)

Conclusion: Unauthorized egress blocked ✅, Approved endpoints allowed ✅
EOF

cat restricted-results.txt
```

---

## Part 3: Comparison and Validation

### Side-by-Side Comparison

```bash
# Create comparison report
cat > comparison-report.md <<'EOF'
# AKS Egress Restriction Comparison

## Configuration Comparison

| Aspect | Non-Restricted | Egress-Restricted |
|--------|----------------|-------------------|
| **Default Route** | 0.0.0.0/0 → Internet | 0.0.0.0/0 → Firewall (10.0.1.4) |
| **NSG Outbound** | Allow Internet | Deny Internet |
| **AKS Outbound Type** | loadBalancer | userDefinedRouting |
| **Network Policy** | None | Calico |
| **GitHub API** | ✅ Allowed | ❌ Blocked |
| **Google** | ✅ Allowed | ❌ Blocked |
| **MCR** | ✅ Allowed | ✅ Allowed (FW rule) |
| **Azure APIs** | ✅ Allowed | ✅ Allowed (FW rule) |

## Security Benefits

### Egress-Restricted Advantages:
1. ✅ Prevents data exfiltration to unauthorized endpoints
2. ✅ Centralized logging of all egress traffic
3. ✅ Consistent enforcement across all workloads
4. ✅ Explicit allow list (zero-trust model)
5. ✅ Audit trail for compliance

### Trade-offs:
1. ⚠️ Initial setup complexity (firewall rules)
2. ⚠️ Requires firewall rule updates for new endpoints
3. ⚠️ Additional cost (Azure Firewall)
4. ⚠️ Potential latency (firewall inspection)

## Compliance Benefits

Egress restriction helps meet requirements for:
- **PCI-DSS**: Requirement 1 (Network Security Controls)
- **HIPAA**: Access controls and audit logging
- **SOC 2**: Logical access controls
- **ISO 27001**: Network security management
- **NIST 800-53**: AC-4 (Information Flow Enforcement)

EOF

cat comparison-report.md
```

### Verify Firewall Logging

```bash
# Query Firewall logs for blocked traffic
az monitor log-analytics query \
  --workspace "<log-analytics-workspace-id>" \
  --analytics-query "
    AzureDiagnostics
    | where ResourceType == 'AZUREFIREWALLS'
    | where Category == 'AzureFirewallApplicationRule'
    | where TimeGenerated > ago(1h)
    | where SourceIp startswith '10.1.'
    | project TimeGenerated, SourceIp, DestinationIp, Fqdn, Action, Protocol
    | order by TimeGenerated desc
    | take 50
  " \
  --output table

# Query for denied connections
az monitor log-analytics query \
  --workspace "<log-analytics-workspace-id>" \
  --analytics-query "
    AzureDiagnostics
    | where ResourceType == 'AZUREFIREWALLS'
    | where Action == 'Deny'
    | where TimeGenerated > ago(1h)
    | summarize DeniedCount=count() by Fqdn
    | order by DeniedCount desc
  " \
  --output table
```

### Visual Network Flow Verification

```bash
# Verify route tables
echo "=== Route Table Verification ==="
az network route-table route list \
  --resource-group rg-spoke-aks-demo \
  --route-table-name rt-aks-demo-restricted \
  --query "[].{Name:name, AddressPrefix:addressPrefix, NextHop:nextHopIpAddress}" \
  --output table

# Verify NSG rules
echo "=== NSG Verification ==="
az network nsg rule list \
  --resource-group rg-spoke-aks-demo \
  --nsg-name nsg-aks-system-demo-restricted \
  --query "[?direction=='Outbound'].{Name:name, Priority:priority, Access:access, Destination:destinationAddressPrefix}" \
  --output table
```

---

## Part 4: Advanced Scenarios

### Scenario A: Private Endpoint Connectivity Test

Private endpoints bypass the firewall - traffic goes directly through VNet peering.

```bash
# Deploy Azure SQL with private endpoint (if not exists)
# Assume: sqlserver-demo.database.windows.net with private endpoint at 10.1.4.10

# Test from restricted cluster
kubectl exec -n egress-test egress-test-restricted -- nslookup sqlserver-demo.database.windows.net
# Expected: Resolves to private IP (10.1.4.x) ✅

kubectl exec -n egress-test egress-test-restricted -- nc -zv sqlserver-demo.database.windows.net 1433
# Expected: Connection succeeds (bypasses firewall) ✅
```

### Scenario B: Testing ACR Pull with Private Endpoint

```bash
# Verify ACR private endpoint
ACR_NAME="acrdemo"

# From restricted cluster
kubectl run test-acr-pull \
  --image=${ACR_NAME}.azurecr.io/nginx:latest \
  --namespace egress-test \
  --restart=Never

# Monitor pull
kubectl describe pod test-acr-pull -n egress-test

# Expected: Image pulls successfully via private endpoint ✅
kubectl delete pod test-acr-pull -n egress-test
```

### Scenario C: Adding New Allowed Endpoint

Demonstrate how to allow a new endpoint (e.g., Docker Hub).

```bash
# SecOps adds firewall rule for Docker Hub
az network firewall policy rule-collection-group collection rule add \
  --policy-name $POLICY_NAME \
  --resource-group $FIREWALL_RG \
  --rule-collection-group-name "AKS-Egress-Rules" \
  --collection-name "Azure-PaaS-Services" \
  --rule-type ApplicationRule \
  --name "DockerHub" \
  --source-addresses "10.1.0.0/16" \
  --protocols "Https=443" \
  --target-fqdns \
    "hub.docker.com" \
    "registry-1.docker.io" \
    "auth.docker.io" \
    "production.cloudflare.docker.com"

# Wait for rule propagation (~30 seconds)
sleep 30

# Test from restricted cluster
kubectl exec -n egress-test egress-test-restricted -- curl -I -s -o /dev/null -w "%{http_code}\n" https://hub.docker.com
# Expected: Now works ✅

# Pull image from Docker Hub
kubectl run test-dockerhub \
  --image=nginx:alpine \
  --namespace egress-test \
  --restart=Never

kubectl wait --for=condition=ready pod/test-dockerhub -n egress-test --timeout=120s
kubectl delete pod test-dockerhub -n egress-test
```

### Scenario D: Network Policy Enforcement (Pod-Level)

Demonstrate pod-to-pod restrictions with Calico/Azure Network Policy.

```bash
# Deploy two test pods
kubectl run pod-a --image=nginx --namespace egress-test --labels="app=pod-a"
kubectl run pod-b --image=nginx --namespace egress-test --labels="app=pod-b"

kubectl wait --for=condition=ready pod/pod-a -n egress-test --timeout=120s
kubectl wait --for=condition=ready pod/pod-b -n egress-test --timeout=120s

# Get pod IPs
POD_A_IP=$(kubectl get pod pod-a -n egress-test -o jsonpath='{.status.podIP}')
POD_B_IP=$(kubectl get pod pod-b -n egress-test -o jsonpath='{.status.podIP}')

# Test connectivity before policy
kubectl exec -n egress-test egress-test-restricted -- curl -s -o /dev/null -w "%{http_code}\n" http://${POD_A_IP}
# Expected: 200 ✅

# Apply deny-all network policy
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-egress
  namespace: egress-test
spec:
  podSelector:
    matchLabels:
      app: pod-a
  policyTypes:
  - Egress
  egress: []  # Empty = deny all
EOF

# Test connectivity after policy
kubectl exec -n egress-test egress-test-restricted -- timeout 5 curl -s -o /dev/null -w "%{http_code}\n" http://${POD_A_IP} || echo "BLOCKED by Network Policy ✅"

# Cleanup
kubectl delete networkpolicy deny-all-egress -n egress-test
kubectl delete pod pod-a pod-b -n egress-test
```

---

## Troubleshooting

### Issue 1: AKS Nodes Not Ready

**Symptoms:** Nodes stuck in NotReady state after enabling egress restriction.

**Cause:** Missing firewall rules for AKS required endpoints.

**Solution:**
```bash
# Verify firewall rules include ALL AKS required endpoints
az network firewall policy rule-collection-group collection rule list \
  --policy-name $POLICY_NAME \
  --resource-group $FIREWALL_RG \
  --rule-collection-group-name "AKS-Egress-Rules" \
  --collection-name "AKS-Required-FQDNs"

# Check node logs
kubectl describe node <node-name>

# Verify route table
az network route-table route show \
  --resource-group rg-spoke-aks-demo \
  --route-table-name rt-aks \
  --name default-via-firewall
```

### Issue 2: Pods Cannot Pull Images

**Symptoms:** ImagePullBackOff errors.

**Root Causes:**
1. ACR endpoint not allowed in firewall
2. Private endpoint not configured
3. DNS resolution issues

**Solutions:**
```bash
# Check DNS resolution from pod
kubectl run dns-test --image=busybox --restart=Never -n egress-test -- nslookup acrdemo.azurecr.io
kubectl logs dns-test -n egress-test
# Should resolve to private IP (10.1.x.x)

# Check firewall rules for ACR
az network firewall policy rule-collection-group collection rule list \
  --policy-name $POLICY_NAME \
  --resource-group $FIREWALL_RG \
  --rule-collection-group-name "AKS-Egress-Rules" \
  --collection-name "Azure-PaaS-Services" \
  | grep -i "azurecr"

# Verify private endpoint
az network private-endpoint list \
  --resource-group rg-spoke-aks-demo \
  --query "[?contains(name, 'acr')].{Name:name, ProvisioningState:provisioningState}" \
  --output table
```

### Issue 3: Firewall Logs Not Showing Traffic

**Symptoms:** No logs in Log Analytics.

**Solution:**
```bash
# Verify diagnostic settings
az monitor diagnostic-settings list \
  --resource "/subscriptions/<sub-id>/resourceGroups/rg-hub/providers/Microsoft.Network/azureFirewalls/afw-hub" \
  --query "[].{Name:name, Enabled:logs[].enabled}" \
  --output table

# Create diagnostic setting if missing
az monitor diagnostic-settings create \
  --name "firewall-logs" \
  --resource "/subscriptions/<sub-id>/resourceGroups/rg-hub/providers/Microsoft.Network/azureFirewalls/afw-hub" \
  --workspace "<log-analytics-workspace-id>" \
  --logs '[{"category": "AzureFirewallApplicationRule", "enabled": true}, {"category": "AzureFirewallNetworkRule", "enabled": true}]'
```

### Issue 4: Private Endpoint Not Resolving

**Symptoms:** Private endpoint resolves to public IP instead of private IP.

**Solution:**
```bash
# Check private DNS zone link to spoke VNet
az network private-dns link vnet list \
  --resource-group rg-hub \
  --zone-name privatelink.azurecr.io \
  --query "[].{Name:name, VirtualNetwork:virtualNetwork.id, ProvisioningState:provisioningState}" \
  --output table

# Test DNS resolution from pod
kubectl exec -n egress-test egress-test-restricted -- nslookup acrdemo.azurecr.io
# Should return: 10.1.x.x (private IP)

# If resolving to public IP, check VNet peering and DNS settings
az network vnet show \
  --resource-group rg-spoke-aks-demo \
  --name vnet-spoke-aks-demo \
  --query "dhcpOptions.dnsServers" \
  --output tsv
# Should be empty or point to Azure DNS (168.63.129.16)
```

---

## Cleanup

### Remove Test Workloads

```bash
# Delete test namespaces
kubectl delete namespace egress-test --ignore-not-found

# Remove test pods
kubectl delete pod --all -n egress-test --ignore-not-found
```

### Optional: Remove Demo Infrastructure

```bash
# Remove restricted spoke
cd /workspaces/aks-lz-ghcp/spoke-aks
terraform destroy -var-file=environments/demo-restricted.tfvars -auto-approve

# Remove baseline spoke
terraform destroy -var-file=environments/demo-baseline.tfvars -auto-approve

# Remove firewall rules (optional)
az network firewall policy rule-collection-group delete \
  --name "AKS-Egress-Rules" \
  --policy-name $POLICY_NAME \
  --resource-group $FIREWALL_RG \
  --yes
```

---

## Demo Script for Presentations

### 5-Minute Executive Demo

```bash
#!/bin/bash
# Quick demo script for executive presentations

echo "=== AKS Egress Restriction Demo ==="
echo ""

echo "Step 1: Testing Non-Restricted AKS (Baseline)"
echo "✅ Can access GitHub API"
kubectl exec -n egress-test egress-test-baseline -- curl -s -o /dev/null -w "Status: %{http_code}\n" https://api.github.com

echo "✅ Can access Google"
kubectl exec -n egress-test egress-test-baseline -- curl -s -o /dev/null -w "Status: %{http_code}\n" https://www.google.com

echo ""
echo "Step 2: Testing Egress-Restricted AKS"
echo "❌ Cannot access GitHub API (blocked by firewall)"
kubectl exec -n egress-test egress-test-restricted -- timeout 5 curl -s -o /dev/null -w "Status: %{http_code}\n" https://api.github.com || echo "Status: BLOCKED ✅"

echo "❌ Cannot access Google (blocked by firewall)"
kubectl exec -n egress-test egress-test-restricted -- timeout 5 curl -s -o /dev/null -w "Status: %{http_code}\n" https://www.google.com || echo "Status: BLOCKED ✅"

echo "✅ CAN access Microsoft Container Registry (allowed)"
kubectl exec -n egress-test egress-test-restricted -- curl -s -o /dev/null -w "Status: %{http_code}\n" https://mcr.microsoft.com

echo ""
echo "=== Summary ==="
echo "Egress restriction successfully blocks unauthorized external access"
echo "while allowing approved Azure services. ✅"
echo ""
echo "Benefits: Data exfiltration prevention, compliance, audit trails"
```

### 15-Minute Technical Deep Dive

```bash
#!/bin/bash
# Extended demo with firewall logs and network flow analysis

# Run executive demo first
./quick-demo.sh

echo ""
echo "=== Deep Dive: Network Flow Analysis ==="

echo "1. Route Table Configuration"
az network route-table route list \
  --resource-group rg-spoke-aks-demo \
  --route-table-name rt-aks-demo-restricted \
  --output table

echo ""
echo "2. NSG Outbound Rules"
az network nsg rule list \
  --resource-group rg-spoke-aks-demo \
  --nsg-name nsg-aks-system-demo-restricted \
  --query "[?direction=='Outbound']" \
  --output table

echo ""
echo "3. Firewall Logs (Last 10 Denied Connections)"
az monitor log-analytics query \
  --workspace "<workspace-id>" \
  --analytics-query "
    AzureDiagnostics
    | where Action == 'Deny'
    | where TimeGenerated > ago(30m)
    | project TimeGenerated, SourceIp, Fqdn, Action
    | take 10
  " \
  --output table

echo ""
echo "4. Private Endpoint Connectivity (Bypasses Firewall)"
kubectl exec -n egress-test egress-test-restricted -- nslookup acrdemo.azurecr.io
# Should resolve to private IP

echo ""
echo "=== Demo Complete ==="
```

---

## Conclusion

This demo demonstrates:
1. ✅ **Baseline vs. Restricted**: Clear comparison of security postures
2. ✅ **Effectiveness**: Unauthorized egress blocked, approved traffic allowed
3. ✅ **Private Endpoints**: Azure PaaS services accessible via private connectivity
4. ✅ **Logging**: Full audit trail of egress attempts
5. ✅ **Flexibility**: Easy to add new allowed endpoints as needed

**Key Takeaway for SecOps:** Egress restriction provides defense-in-depth against data exfiltration and unauthorized connectivity while maintaining operational flexibility through firewall rule management.

**Next Steps:**
1. Review firewall rules with application teams
2. Establish change management process for new endpoints
3. Configure alerting on denied connections
4. Document approved endpoints in service catalog
5. Implement automated testing in CI/CD pipelines
