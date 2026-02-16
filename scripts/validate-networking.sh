#!/bin/bash
# ============================================================================
# AKS Landing Zone — Unified Validation Script
# ============================================================================
# Validates hub/spoke infrastructure, DNS resolution, AKS connectivity,
# and in-cluster networking.
#
# Usage:
#   ./validate-networking.sh <environment> [--mode=infra|full]
#
# Modes:
#   --mode=infra  Sections 1-3: pre-flight, hub infra, spoke infra
#                 Safe to run from pipeline agents (no private network needed)
#   --mode=full   All sections including DNS resolution, AKS connectivity,
#                 and in-cluster network tests (requires jump box / private access)
#
# Examples:
#   ./validate-networking.sh prod --mode=infra   # pipeline post-apply validation
#   ./validate-networking.sh prod --mode=full    # manual from jump box via Bastion
#   ./validate-networking.sh prod                # defaults to full
# ============================================================================

set -e

ENVIRONMENT=${1:-dev}
MODE="full"

# Parse flags
for arg in "$@"; do
  case "$arg" in
    --mode=*) MODE="${arg#*=}" ;;
  esac
done

if [[ "$MODE" != "infra" && "$MODE" != "full" ]]; then
  echo "ERROR: Invalid mode '$MODE'. Use --mode=infra or --mode=full"
  exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0
WARNINGS=0

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; ((PASSED++)); }
log_error()   { echo -e "${RED}[✗]${NC} $1"; ((FAILED++)); }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; ((WARNINGS++)); }

check_command() {
  if command -v "$1" &> /dev/null; then
    log_success "Command '$1' is available"
    return 0
  else
    log_error "Command '$1' is not installed"
    return 1
  fi
}

# ============================================================================
# Section 1: Pre-flight Checks
# ============================================================================

log_info "Starting AKS Landing Zone validation for environment: $ENVIRONMENT (mode: $MODE)"
echo ""
log_info "=== Section 1: Pre-flight Checks ==="
check_command az
check_command jq

if [[ "$MODE" == "full" ]]; then
  check_command kubectl
  if ! command -v nslookup &> /dev/null; then
    log_warning "nslookup not available — DNS resolution tests will be skipped"
    NSLOOKUP_AVAILABLE=false
  else
    NSLOOKUP_AVAILABLE=true
  fi
fi

if az account show &> /dev/null; then
  SUBSCRIPTION=$(az account show --query name -o tsv)
  log_success "Logged into Azure subscription: $SUBSCRIPTION"
else
  log_error "Not logged into Azure. Run 'az login' first."
  exit 1
fi

echo ""

# ============================================================================
# Section 2: Hub Infrastructure Validation
# ============================================================================

log_info "=== Section 2: Hub Infrastructure Validation ==="

# Discover hub resource group
if [[ -n "${HUB_RG_OVERRIDE:-}" ]]; then
  HUB_RG="$HUB_RG_OVERRIDE"
  log_info "Using overridden hub resource group: $HUB_RG"
else
  HUB_RG=$(az group list --query "[?starts_with(name, 'rg-hub-')].name | [0]" -o tsv 2>/dev/null || true)
  if [[ -z "$HUB_RG" || "$HUB_RG" == "null" ]]; then
    HUB_RG="rg-hub-eus2-${ENVIRONMENT}"
    log_warning "Could not auto-discover hub resource group. Falling back to: $HUB_RG"
  else
    log_info "Auto-discovered hub resource group: $HUB_RG"
  fi
fi

if az group show -n "$HUB_RG" &> /dev/null; then
  log_success "Hub resource group exists: $HUB_RG"
else
  log_error "Hub resource group not found: $HUB_RG"
fi

# Hub VNet
HUB_VNET=$(az network vnet list -g "$HUB_RG" --query "[0].name" -o tsv 2>/dev/null || true)
if [[ -n "$HUB_VNET" ]]; then
  log_success "Hub VNet found: $HUB_VNET"
  ADDRESS_SPACE=$(az network vnet show -g "$HUB_RG" -n "$HUB_VNET" --query "addressSpace.addressPrefixes[0]" -o tsv)
  if [[ "$ADDRESS_SPACE" == "10.0.0.0/16" ]]; then
    log_success "Hub VNet address space correct: $ADDRESS_SPACE"
  else
    log_warning "Hub VNet address space: $ADDRESS_SPACE (expected 10.0.0.0/16)"
  fi
else
  log_error "Hub VNet not found in $HUB_RG"
fi

# Azure Firewall
FIREWALL=$(az network firewall list -g "$HUB_RG" --query "[0].name" -o tsv 2>/dev/null || true)
if [[ -n "$FIREWALL" ]]; then
  log_success "Azure Firewall found: $FIREWALL"
  FW_IP=$(az network firewall show -g "$HUB_RG" -n "$FIREWALL" --query "ipConfigurations[0].privateIPAddress" -o tsv 2>/dev/null || true)
  if [[ -n "$FW_IP" ]]; then
    log_success "Firewall private IP: $FW_IP"
  else
    log_warning "Could not retrieve firewall private IP"
  fi
else
  log_warning "Azure Firewall not found (may be disabled)"
fi

# DNS Resolver
DNS_RESOLVER=$(az dns-resolver list -g "$HUB_RG" --query "[0].name" -o tsv 2>/dev/null || true)
if [[ -n "$DNS_RESOLVER" ]]; then
  log_success "DNS Resolver found: $DNS_RESOLVER"

  INBOUND_EP=$(az dns-resolver inbound-endpoint list -g "$HUB_RG" --dns-resolver-name "$DNS_RESOLVER" --query "[0].name" -o tsv 2>/dev/null || true)
  if [[ -n "$INBOUND_EP" ]]; then
    log_success "DNS Resolver inbound endpoint: $INBOUND_EP"
    INBOUND_IP=$(az dns-resolver inbound-endpoint show -g "$HUB_RG" --dns-resolver-name "$DNS_RESOLVER" -n "$INBOUND_EP" --query "ipConfigurations[0].privateIPAddress" -o tsv 2>/dev/null || true)
    log_info "Inbound endpoint IP: $INBOUND_IP (spokes use this for DNS)"
  else
    log_warning "DNS Resolver inbound endpoint not found"
  fi

  OUTBOUND_EP=$(az dns-resolver outbound-endpoint list -g "$HUB_RG" --dns-resolver-name "$DNS_RESOLVER" --query "[0].name" -o tsv 2>/dev/null || true)
  if [[ -n "$OUTBOUND_EP" ]]; then
    log_success "DNS Resolver outbound endpoint found"
  else
    log_warning "DNS Resolver outbound endpoint not found"
  fi
else
  log_error "DNS Resolver not found in $HUB_RG"
fi

# Private DNS Zones
EXPECTED_ZONES=("privatelink.azurecr.io" "privatelink.vaultcore.azure.net" "privatelink.eastus2.azmk8s.io")
for ZONE in "${EXPECTED_ZONES[@]}"; do
  if az network private-dns zone show -g "$HUB_RG" -n "$ZONE" &> /dev/null; then
    log_success "Private DNS zone exists: $ZONE"
    LINK_COUNT=$(az network private-dns link vnet list -g "$HUB_RG" -z "$ZONE" --query "length(@)" -o tsv 2>/dev/null || echo "0")
    if [[ "$LINK_COUNT" -gt 0 ]]; then
      log_success "DNS zone $ZONE has $LINK_COUNT VNet link(s)"
    else
      log_warning "DNS zone $ZONE has no VNet links"
    fi
  else
    log_error "Private DNS zone not found: $ZONE"
  fi
done

# Log Analytics Workspace
LAW=$(az monitor log-analytics workspace list -g "$HUB_RG" --query "[0].name" -o tsv 2>/dev/null || true)
if [[ -n "$LAW" ]]; then
  log_success "Log Analytics Workspace found: $LAW"
else
  log_error "Log Analytics Workspace not found"
fi

echo ""

# ============================================================================
# Section 3: Spoke Infrastructure Validation
# ============================================================================

log_info "=== Section 3: Spoke Infrastructure Validation ==="

SPOKE_RG="rg-aks-eus2-${ENVIRONMENT}"
if az group show -n "$SPOKE_RG" &> /dev/null; then
  log_success "Spoke resource group exists: $SPOKE_RG"
else
  log_error "Spoke resource group not found: $SPOKE_RG"
fi

# Spoke VNet
SPOKE_VNET=$(az network vnet list -g "$SPOKE_RG" --query "[0].name" -o tsv 2>/dev/null || true)
if [[ -n "$SPOKE_VNET" ]]; then
  log_success "Spoke VNet found: $SPOKE_VNET"

  DNS_SERVERS=$(az network vnet show -g "$SPOKE_RG" -n "$SPOKE_VNET" --query "dhcpOptions.dnsServers" -o json 2>/dev/null || echo "[]")
  if echo "$DNS_SERVERS" | grep -q "10.0.6"; then
    log_success "Spoke VNet DNS servers point to hub DNS Resolver"
  else
    log_warning "Spoke VNet DNS servers: $DNS_SERVERS (expected hub resolver IP)"
  fi

  PEERING=$(az network vnet peering list -g "$SPOKE_RG" --vnet-name "$SPOKE_VNET" --query "[0].name" -o tsv 2>/dev/null || true)
  if [[ -n "$PEERING" ]]; then
    PEERING_STATE=$(az network vnet peering show -g "$SPOKE_RG" --vnet-name "$SPOKE_VNET" -n "$PEERING" --query "peeringState" -o tsv 2>/dev/null || true)
    if [[ "$PEERING_STATE" == "Connected" ]]; then
      log_success "VNet peering state: $PEERING_STATE"
    else
      log_error "VNet peering state: $PEERING_STATE (expected Connected)"
    fi
  else
    log_error "VNet peering not found"
  fi
else
  log_error "Spoke VNet not found"
fi

# AKS Cluster config checks
AKS_CLUSTER=$(az aks list -g "$SPOKE_RG" --query "[0].name" -o tsv 2>/dev/null || true)
if [[ -n "$AKS_CLUSTER" ]]; then
  log_success "AKS cluster found: $AKS_CLUSTER"

  AKS_VERSION=$(az aks show -g "$SPOKE_RG" -n "$AKS_CLUSTER" --query "kubernetesVersion" -o tsv 2>/dev/null || true)
  log_info "Kubernetes version: $AKS_VERSION"

  NETWORK_PLUGIN=$(az aks show -g "$SPOKE_RG" -n "$AKS_CLUSTER" --query "networkProfile.networkPlugin" -o tsv 2>/dev/null || true)
  NETWORK_MODE=$(az aks show -g "$SPOKE_RG" -n "$AKS_CLUSTER" --query "networkProfile.networkPluginMode" -o tsv 2>/dev/null || true)
  NETWORK_DATAPLANE=$(az aks show -g "$SPOKE_RG" -n "$AKS_CLUSTER" --query "networkProfile.networkDataplane" -o tsv 2>/dev/null || true)
  NETWORK_POLICY=$(az aks show -g "$SPOKE_RG" -n "$AKS_CLUSTER" --query "networkProfile.networkPolicy" -o tsv 2>/dev/null || true)

  [[ "$NETWORK_PLUGIN" == "azure" ]] && log_success "Network plugin: azure" || log_warning "Network plugin: $NETWORK_PLUGIN (expected azure)"
  [[ "$NETWORK_MODE" == "overlay" ]] && log_success "Network plugin mode: overlay" || log_warning "Network plugin mode: $NETWORK_MODE (expected overlay)"
  [[ "$NETWORK_DATAPLANE" == "cilium" ]] && log_success "Network dataplane: cilium" || log_warning "Network dataplane: $NETWORK_DATAPLANE (expected cilium)"
  [[ "$NETWORK_POLICY" == "cilium" ]] && log_success "Network policy: cilium" || log_warning "Network policy: $NETWORK_POLICY (expected cilium)"

  IS_PRIVATE=$(az aks show -g "$SPOKE_RG" -n "$AKS_CLUSTER" --query "apiServerAccessProfile.enablePrivateCluster" -o tsv 2>/dev/null || true)
  [[ "$IS_PRIVATE" == "true" ]] && log_success "AKS is a private cluster" || log_warning "AKS is not a private cluster"

  NODE_POOLS=$(az aks nodepool list -g "$SPOKE_RG" --cluster-name "$AKS_CLUSTER" --query "length(@)" -o tsv 2>/dev/null || echo "0")
  log_info "Node pools: $NODE_POOLS"
else
  log_error "AKS cluster not found"
fi

# ACR
ACR=$(az acr list -g "$SPOKE_RG" --query "[0].name" -o tsv 2>/dev/null || true)
if [[ -n "$ACR" ]]; then
  log_success "Azure Container Registry found: $ACR"
  ACR_SKU=$(az acr show -n "$ACR" --query "sku.name" -o tsv 2>/dev/null || true)
  [[ "$ACR_SKU" == "Premium" ]] && log_success "ACR SKU: Premium" || log_warning "ACR SKU: $ACR_SKU (expected Premium)"
  PE_COUNT=$(az network private-endpoint list -g "$SPOKE_RG" --query "[?contains(name, 'acr')].name" -o tsv 2>/dev/null | wc -l)
  [[ "$PE_COUNT" -gt 0 ]] && log_success "ACR has private endpoint" || log_warning "ACR private endpoint not found"
else
  log_error "Azure Container Registry not found"
fi

# Key Vault
KV=$(az keyvault list -g "$SPOKE_RG" --query "[0].name" -o tsv 2>/dev/null || true)
if [[ -n "$KV" ]]; then
  log_success "Key Vault found: $KV"
  PE_COUNT=$(az network private-endpoint list -g "$SPOKE_RG" --query "[?contains(name, 'kv')].name" -o tsv 2>/dev/null | wc -l)
  [[ "$PE_COUNT" -gt 0 ]] && log_success "Key Vault has private endpoint" || log_warning "Key Vault private endpoint not found"
else
  log_error "Key Vault not found"
fi

# Spoke Jump Box
SPOKE_JUMPBOX=$(az vm list -g "$SPOKE_RG" --query "[?contains(name, 'jumpbox')].name" -o tsv 2>/dev/null | head -1)
if [[ -n "$SPOKE_JUMPBOX" ]]; then
  log_success "Spoke jump box VM found: $SPOKE_JUMPBOX"
else
  log_warning "Spoke jump box VM not found"
fi

echo ""

# ============================================================================
# Sections 4-6: Full mode only (requires private network access)
# ============================================================================

if [[ "$MODE" == "infra" ]]; then
  log_info "Mode is 'infra' — skipping DNS, AKS connectivity, and in-cluster tests."
  log_info "Run with --mode=full from jump box via Bastion for complete validation."
  echo ""
else

  # ==========================================================================
  # Section 4: DNS Resolution Tests
  # ==========================================================================

  log_info "=== Section 4: DNS Resolution Tests ==="

  if [[ "$NSLOOKUP_AVAILABLE" != "true" ]]; then
    log_warning "Skipping DNS resolution tests (nslookup not available)"
  else

  # AKS API server FQDN
  if [[ -n "$AKS_CLUSTER" ]]; then
    AKS_FQDN=$(az aks show -g "$SPOKE_RG" -n "$AKS_CLUSTER" --query "privateFqdn" -o tsv 2>/dev/null || true)
    if [[ -n "$AKS_FQDN" ]]; then
      if nslookup "$AKS_FQDN" &> /dev/null; then
        AKS_IP=$(nslookup "$AKS_FQDN" 2>/dev/null | grep -A1 "Name:" | grep "Address:" | awk '{print $2}')
        log_success "AKS API server resolves: $AKS_FQDN → $AKS_IP"
      else
        log_error "AKS API server DNS resolution failed: $AKS_FQDN"
      fi
    else
      log_warning "Could not get AKS private FQDN"
    fi
  fi

  # ACR FQDN
  if [[ -n "$ACR" ]]; then
    ACR_FQDN=$(az acr show -n "$ACR" --query "loginServer" -o tsv 2>/dev/null || true)
    if [[ -n "$ACR_FQDN" ]]; then
      if nslookup "$ACR_FQDN" &> /dev/null; then
        log_success "ACR DNS resolves: $ACR_FQDN"
      else
        log_error "ACR DNS resolution failed: $ACR_FQDN"
      fi
    fi
  fi

  # Key Vault FQDN
  if [[ -n "$KV" ]]; then
    KV_FQDN="${KV}.vault.azure.net"
    if nslookup "$KV_FQDN" &> /dev/null; then
      log_success "Key Vault DNS resolves: $KV_FQDN"
    else
      log_error "Key Vault DNS resolution failed: $KV_FQDN"
    fi
  fi

  fi # end nslookup available check

  echo ""

  # ==========================================================================
  # Section 5: AKS Connectivity
  # ==========================================================================

  log_info "=== Section 5: AKS Connectivity ==="

  if [[ -n "$AKS_CLUSTER" ]]; then
    if az aks get-credentials -g "$SPOKE_RG" -n "$AKS_CLUSTER" --overwrite-existing &> /dev/null; then
      log_success "Retrieved AKS credentials"

      if kubectl get nodes &> /dev/null; then
        NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
        log_success "kubectl connected to cluster ($NODE_COUNT nodes)"

        NOT_READY=$(kubectl get nodes --no-headers | grep -cv "Ready" || true)
        if [[ "$NOT_READY" -eq 0 ]]; then
          log_success "All nodes are Ready"
        else
          log_warning "$NOT_READY node(s) are not Ready"
        fi
      else
        log_error "kubectl cannot connect to cluster"
      fi
    else
      log_warning "Could not retrieve AKS credentials (private cluster access required)"
    fi
  fi

  echo ""

  # ==========================================================================
  # Section 6: In-Cluster Network Tests
  # ==========================================================================

  log_info "=== Section 6: In-Cluster Network Tests ==="

  if kubectl get nodes &> /dev/null 2>&1; then
    NAMESPACE="network-test"
    log_info "Creating test namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - > /dev/null

    log_info "Deploying network test pod..."
    cat <<EOF | kubectl apply -f - > /dev/null
apiVersion: v1
kind: Pod
metadata:
  name: network-test
  namespace: $NAMESPACE
spec:
  containers:
  - name: network-tools
    image: nicolaka/netshoot:v0.11
    command:
      - sleep
      - "3600"
  restartPolicy: Never
EOF

    log_info "Waiting for test pod to be ready..."
    if kubectl wait --for=condition=Ready pod/network-test -n "$NAMESPACE" --timeout=120s > /dev/null 2>&1; then
      log_success "Test pod is ready"

      # External DNS
      if kubectl exec -n "$NAMESPACE" network-test -- nslookup www.microsoft.com &> /dev/null; then
        log_success "External DNS resolution works (www.microsoft.com)"
      else
        log_error "External DNS resolution failed"
      fi

      # Azure service DNS
      if kubectl exec -n "$NAMESPACE" network-test -- nslookup management.azure.com &> /dev/null; then
        log_success "Azure service DNS works (management.azure.com)"
      else
        log_error "Azure service DNS resolution failed"
      fi

      # K8s internal DNS
      if kubectl exec -n "$NAMESPACE" network-test -- nslookup kubernetes.default.svc.cluster.local &> /dev/null; then
        log_success "Kubernetes internal DNS works"
      else
        log_error "Kubernetes internal DNS failed"
      fi

      # Outbound HTTPS
      if kubectl exec -n "$NAMESPACE" network-test -- curl -s -o /dev/null -w "%{http_code}" --max-time 10 https://www.microsoft.com | grep -q "200\|301\|302"; then
        log_success "Outbound HTTPS connectivity works"
      else
        log_error "Outbound HTTPS connectivity failed"
      fi

      # Azure API
      if kubectl exec -n "$NAMESPACE" network-test -- curl -s -o /dev/null -w "%{http_code}" --max-time 10 https://management.azure.com | grep -q "200\|401"; then
        log_success "Azure API connectivity works"
      else
        log_error "Azure API connectivity failed"
      fi

      # MCR connectivity
      if kubectl exec -n "$NAMESPACE" network-test -- curl -s -o /dev/null -w "%{http_code}" --max-time 10 https://mcr.microsoft.com | grep -q "200\|301\|302"; then
        log_success "MCR connectivity works"
      else
        log_error "MCR connectivity failed"
      fi

      # Pod overlay CIDR check
      POD_IP=$(kubectl get pod network-test -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
      NODE_IP=$(kubectl get pod network-test -n "$NAMESPACE" -o jsonpath='{.status.hostIP}')
      log_info "Pod IP: $POD_IP | Node IP: $NODE_IP"

      if [[ "$POD_IP" == 192.168.* ]]; then
        log_success "Pod IP is from overlay CIDR (192.168.0.0/16)"
      else
        log_error "Pod IP not from expected overlay CIDR (got $POD_IP, expected 192.168.x.x)"
      fi
    else
      log_error "Test pod failed to become ready"
    fi

    # Cleanup
    log_info "Cleaning up test resources..."
    kubectl delete namespace "$NAMESPACE" --wait=false > /dev/null 2>&1 || true
    log_success "Test namespace deleted"
  else
    log_warning "Skipping in-cluster tests (kubectl not connected)"
  fi

  echo ""
fi

# ============================================================================
# Section 7: Summary
# ============================================================================

log_info "=== Validation Summary ==="
echo -e "${GREEN}Passed:${NC}   $PASSED"
echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
echo -e "${RED}Failed:${NC}   $FAILED"
echo ""

if [[ $FAILED -eq 0 ]]; then
  log_success "Validation completed successfully! (mode: $MODE)"
  exit 0
else
  log_error "Validation completed with $FAILED error(s)"
  exit 1
fi
