#!/bin/bash
# ============================================================================
# AKS Landing Zone - Deployment Validation Script
# ============================================================================
# This script validates that hub and spoke infrastructure is correctly deployed
# and all networking, DNS, and security configurations are working as expected.
#
# Usage: ./validate-deployment.sh <environment>
# Example: ./validate-deployment.sh dev

set -e

ENVIRONMENT=${1:-dev}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
    ((PASSED++))
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
    ((FAILED++))
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
    ((WARNINGS++))
}

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
# Pre-flight Checks
# ============================================================================

log_info "Starting AKS Landing Zone validation for environment: $ENVIRONMENT"
echo ""

log_info "=== Pre-flight Checks ==="
check_command az
check_command kubectl
check_command jq

# Check Azure CLI login
if az account show &> /dev/null; then
    SUBSCRIPTION=$(az account show --query name -o tsv)
    log_success "Logged into Azure subscription: $SUBSCRIPTION"
else
    log_error "Not logged into Azure. Run 'az login' first."
    exit 1
fi

echo ""

# ============================================================================
# Hub Infrastructure Validation
# ============================================================================

log_info "=== Hub Infrastructure Validation ==="

# Hub resource group
if [ -n "$HUB_RG_OVERRIDE" ]; then
    # Allow explicit override of the hub resource group name (e.g. from CI or env config)
    HUB_RG="$HUB_RG_OVERRIDE"
    log_info "Using overridden hub resource group: $HUB_RG"
else
    # Try to discover a hub resource group by convention (any group starting with rg-hub-eus2-)
    HUB_RG=$(az group list --query "[?starts_with(name, 'rg-hub-eus2-')].name | [0]" -o tsv 2>/dev/null || true)

    if [ -z "$HUB_RG" ] || [ "$HUB_RG" == "null" ]; then
        # Fallback to legacy pattern using the environment suffix
        HUB_RG="rg-hub-eus2-${ENVIRONMENT}"
        log_warning "Could not auto-discover hub resource group. Falling back to pattern: $HUB_RG"
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
HUB_VNET=$(az network vnet list -g "$HUB_RG" --query "[0].name" -o tsv 2>/dev/null)
if [ -n "$HUB_VNET" ]; then
    log_success "Hub VNet found: $HUB_VNET"
    
    # Check VNet address space
    ADDRESS_SPACE=$(az network vnet show -g "$HUB_RG" -n "$HUB_VNET" --query "addressSpace.addressPrefixes[0]" -o tsv)
    if [ "$ADDRESS_SPACE" == "10.0.0.0/16" ]; then
        log_success "Hub VNet address space is correct: $ADDRESS_SPACE"
    else
        log_warning "Hub VNet address space is: $ADDRESS_SPACE (expected 10.0.0.0/16)"
    fi
else
    log_error "Hub VNet not found in $HUB_RG"
fi

# Azure Firewall
FIREWALL=$(az network firewall list -g "$HUB_RG" --query "[0].name" -o tsv 2>/dev/null)
if [ -n "$FIREWALL" ]; then
    log_success "Azure Firewall found: $FIREWALL"
    
    # Get firewall private IP
    FW_IP=$(az network firewall show -g "$HUB_RG" -n "$FIREWALL" --query "ipConfigurations[0].privateIPAddress" -o tsv)
    if [ -n "$FW_IP" ]; then
        log_success "Firewall private IP: $FW_IP"
    else
        log_warning "Could not retrieve firewall private IP"
    fi
else
    log_warning "Azure Firewall not found (may be disabled for cost savings)"
fi

# DNS Resolver
DNS_RESOLVER=$(az dns-resolver list -g "$HUB_RG" --query "[0].name" -o tsv 2>/dev/null)
if [ -n "$DNS_RESOLVER" ]; then
    log_success "DNS Resolver found: $DNS_RESOLVER"
    
    # Check inbound endpoint
    INBOUND_EP=$(az dns-resolver inbound-endpoint list -g "$HUB_RG" --dns-resolver-name "$DNS_RESOLVER" --query "[0].name" -o tsv 2>/dev/null)
    if [ -n "$INBOUND_EP" ]; then
        log_success "DNS Resolver inbound endpoint found: $INBOUND_EP"
        INBOUND_IP=$(az dns-resolver inbound-endpoint show -g "$HUB_RG" --dns-resolver-name "$DNS_RESOLVER" -n "$INBOUND_EP" --query "ipConfigurations[0].privateIPAddress" -o tsv)
        log_info "Inbound endpoint IP: $INBOUND_IP (spokes should use this for DNS)"
    else
        log_warning "DNS Resolver inbound endpoint not found"
    fi
    
    # Check outbound endpoint
    OUTBOUND_EP=$(az dns-resolver outbound-endpoint list -g "$HUB_RG" --dns-resolver-name "$DNS_RESOLVER" --query "[0].name" -o tsv 2>/dev/null)
    if [ -n "$OUTBOUND_EP" ]; then
        log_success "DNS Resolver outbound endpoint found: $OUTBOUND_EP"
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
        
        # Check VNet link to hub
        LINK_COUNT=$(az network private-dns link vnet list -g "$HUB_RG" -z "$ZONE" --query "length(@)" -o tsv)
        if [ "$LINK_COUNT" -gt 0 ]; then
            log_success "DNS zone $ZONE has $LINK_COUNT VNet link(s)"
        else
            log_warning "DNS zone $ZONE has no VNet links"
        fi
    else
        log_error "Private DNS zone not found: $ZONE"
    fi
done

# Log Analytics Workspace
LAW=$(az monitor log-analytics workspace list -g "$HUB_RG" --query "[0].name" -o tsv 2>/dev/null)
if [ -n "$LAW" ]; then
    log_success "Log Analytics Workspace found: $LAW"
else
    log_error "Log Analytics Workspace not found"
fi

# Hub Jump Box
HUB_JUMPBOX=$(az vm list -g "$HUB_RG" --query "[?contains(name, 'jumpbox')].name" -o tsv 2>/dev/null | head -1)
if [ -n "$HUB_JUMPBOX" ]; then
    log_success "Hub jump box VM found: $HUB_JUMPBOX"
else
    log_warning "Hub jump box VM not found"
fi

echo ""

# ============================================================================
# Spoke Infrastructure Validation
# ============================================================================

log_info "=== Spoke Infrastructure Validation ==="

# Spoke resource group
SPOKE_RG="rg-aks-eus2-${ENVIRONMENT}"
if az group show -n "$SPOKE_RG" &> /dev/null; then
    log_success "Spoke resource group exists: $SPOKE_RG"
else
    log_error "Spoke resource group not found: $SPOKE_RG"
    exit 1
fi

# Spoke VNet
SPOKE_VNET=$(az network vnet list -g "$SPOKE_RG" --query "[0].name" -o tsv 2>/dev/null)
if [ -n "$SPOKE_VNET" ]; then
    log_success "Spoke VNet found: $SPOKE_VNET"
    
    # Check DNS servers configuration
    DNS_SERVERS=$(az network vnet show -g "$SPOKE_RG" -n "$SPOKE_VNET" --query "dhcpOptions.dnsServers" -o json)
    if echo "$DNS_SERVERS" | grep -q "10.0.6.4"; then
        log_success "Spoke VNet DNS servers configured to use hub DNS Resolver (10.0.6.4)"
    else
        log_warning "Spoke VNet DNS servers: $DNS_SERVERS (expected to include 10.0.6.4)"
    fi
    
    # Check VNet peering
    PEERING=$(az network vnet peering list -g "$SPOKE_RG" --vnet-name "$SPOKE_VNET" --query "[0].name" -o tsv)
    if [ -n "$PEERING" ]; then
        log_success "VNet peering found: $PEERING"
        PEERING_STATE=$(az network vnet peering show -g "$SPOKE_RG" --vnet-name "$SPOKE_VNET" -n "$PEERING" --query "peeringState" -o tsv)
        if [ "$PEERING_STATE" == "Connected" ]; then
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

# AKS Cluster
AKS_CLUSTER=$(az aks list -g "$SPOKE_RG" --query "[0].name" -o tsv 2>/dev/null)
if [ -n "$AKS_CLUSTER" ]; then
    log_success "AKS cluster found: $AKS_CLUSTER"
    
    # Get cluster details
    AKS_VERSION=$(az aks show -g "$SPOKE_RG" -n "$AKS_CLUSTER" --query "kubernetesVersion" -o tsv)
    log_info "Kubernetes version: $AKS_VERSION"
    
    # Check network profile
    NETWORK_PLUGIN=$(az aks show -g "$SPOKE_RG" -n "$AKS_CLUSTER" --query "networkProfile.networkPlugin" -o tsv)
    NETWORK_POLICY=$(az aks show -g "$SPOKE_RG" -n "$AKS_CLUSTER" --query "networkProfile.networkPolicy" -o tsv)
    NETWORK_MODE=$(az aks show -g "$SPOKE_RG" -n "$AKS_CLUSTER" --query "networkProfile.networkPluginMode" -o tsv)
    NETWORK_DATAPLANE=$(az aks show -g "$SPOKE_RG" -n "$AKS_CLUSTER" --query "networkProfile.networkDataplane" -o tsv)
    
    if [ "$NETWORK_PLUGIN" == "azure" ]; then
        log_success "Network plugin: $NETWORK_PLUGIN"
    else
        log_warning "Network plugin: $NETWORK_PLUGIN (expected azure)"
    fi
    
    if [ "$NETWORK_MODE" == "overlay" ]; then
        log_success "Network plugin mode: $NETWORK_MODE (Azure CNI Overlay)"
    else
        log_warning "Network plugin mode: $NETWORK_MODE (expected overlay)"
    fi
    
    if [ "$NETWORK_DATAPLANE" == "cilium" ]; then
        log_success "Network dataplane: $NETWORK_DATAPLANE"
    else
        log_warning "Network dataplane: $NETWORK_DATAPLANE (expected cilium)"
    fi
    
    if [ "$NETWORK_POLICY" == "cilium" ]; then
        log_success "Network policy: $NETWORK_POLICY"
    else
        log_warning "Network policy: $NETWORK_POLICY (expected cilium)"
    fi
    
    # Check if private cluster
    IS_PRIVATE=$(az aks show -g "$SPOKE_RG" -n "$AKS_CLUSTER" --query "apiServerAccessProfile.enablePrivateCluster" -o tsv)
    if [ "$IS_PRIVATE" == "true" ]; then
        log_success "AKS is a private cluster"
    else
        log_warning "AKS is not a private cluster"
    fi
    
    # Check node pools
    NODE_POOLS=$(az aks nodepool list -g "$SPOKE_RG" --cluster-name "$AKS_CLUSTER" --query "length(@)" -o tsv)
    log_info "Node pools: $NODE_POOLS"
    
else
    log_error "AKS cluster not found"
fi

# Azure Container Registry
ACR=$(az acr list -g "$SPOKE_RG" --query "[0].name" -o tsv 2>/dev/null)
if [ -n "$ACR" ]; then
    log_success "Azure Container Registry found: $ACR"
    
    # Check SKU
    ACR_SKU=$(az acr show -n "$ACR" --query "sku.name" -o tsv)
    if [ "$ACR_SKU" == "Premium" ]; then
        log_success "ACR SKU: $ACR_SKU (required for private endpoints)"
    else
        log_warning "ACR SKU: $ACR_SKU (expected Premium)"
    fi
    
    # Check private endpoint
    PE_COUNT=$(az network private-endpoint list -g "$SPOKE_RG" --query "[?contains(name, 'acr')].name" -o tsv | wc -l)
    if [ "$PE_COUNT" -gt 0 ]; then
        log_success "ACR has private endpoint"
    else
        log_warning "ACR private endpoint not found"
    fi
else
    log_error "Azure Container Registry not found"
fi

# Key Vault
KV=$(az keyvault list -g "$SPOKE_RG" --query "[0].name" -o tsv 2>/dev/null)
if [ -n "$KV" ]; then
    log_success "Key Vault found: $KV"
    
    # Check private endpoint
    PE_COUNT=$(az network private-endpoint list -g "$SPOKE_RG" --query "[?contains(name, 'kv')].name" -o tsv | wc -l)
    if [ "$PE_COUNT" -gt 0 ]; then
        log_success "Key Vault has private endpoint"
    else
        log_warning "Key Vault private endpoint not found"
    fi
else
    log_error "Key Vault not found"
fi

# Spoke Jump Box
SPOKE_JUMPBOX=$(az vm list -g "$SPOKE_RG" --query "[?contains(name, 'jumpbox')].name" -o tsv 2>/dev/null | head -1)
if [ -n "$SPOKE_JUMPBOX" ]; then
    log_success "Spoke jump box VM found: $SPOKE_JUMPBOX"
else
    log_warning "Spoke jump box VM not found"
fi

echo ""

# ============================================================================
# AKS Connectivity Test (if kubectl configured)
# ============================================================================

log_info "=== AKS Connectivity Test ==="

# Try to get AKS credentials
if [ -n "$AKS_CLUSTER" ]; then
    if az aks get-credentials -g "$SPOKE_RG" -n "$AKS_CLUSTER" --overwrite-existing &> /dev/null; then
        log_success "Retrieved AKS credentials"
        
        # Test kubectl connectivity
        if kubectl get nodes &> /dev/null; then
            NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
            log_success "kubectl can connect to cluster ($NODE_COUNT nodes)"
            
            # Check node status
            NOT_READY=$(kubectl get nodes --no-headers | grep -v Ready | wc -l)
            if [ "$NOT_READY" -eq 0 ]; then
                log_success "All nodes are Ready"
            else
                log_warning "$NOT_READY node(s) are not Ready"
            fi
        else
            log_warning "kubectl cannot connect to cluster (expected for private clusters without jump box access)"
        fi
    else
        log_warning "Could not retrieve AKS credentials (may require private cluster access)"
    fi
fi

echo ""

# ============================================================================
# Summary
# ============================================================================

log_info "=== Validation Summary ==="
echo -e "${GREEN}Passed:${NC} $PASSED"
echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
echo -e "${RED}Failed:${NC} $FAILED"

echo ""

if [ $FAILED -eq 0 ]; then
    log_success "Deployment validation completed successfully!"
    exit 0
else
    log_error "Deployment validation completed with $FAILED error(s)"
    exit 1
fi
