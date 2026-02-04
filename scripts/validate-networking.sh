#!/bin/bash
# ============================================================================
# AKS Landing Zone - Network Validation Script
# ============================================================================
# This script validates network connectivity, DNS resolution, and routing
# from within the AKS cluster using a test pod.
#
# Prerequisites:
# - kubectl configured with AKS cluster access
# - AKS cluster running and accessible
#
# Usage: ./validate-networking.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0

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

log_info "Starting AKS network validation..."
echo ""

# Check kubectl connectivity
if ! kubectl get nodes &> /dev/null; then
    log_error "Cannot connect to Kubernetes cluster. Ensure kubectl is configured."
    exit 1
fi

log_success "kubectl is connected to cluster"

# Create test namespace
NAMESPACE="network-test"
log_info "Creating test namespace: $NAMESPACE"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - > /dev/null

# Deploy test pod with network tools
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

# Wait for pod to be ready
log_info "Waiting for test pod to be ready..."
kubectl wait --for=condition=Ready pod/network-test -n "$NAMESPACE" --timeout=60s > /dev/null
log_success "Test pod is ready"

echo ""
log_info "=== DNS Resolution Tests ==="

# Test external DNS
if kubectl exec -n "$NAMESPACE" network-test -- nslookup www.microsoft.com &> /dev/null; then
    log_success "External DNS resolution works (www.microsoft.com)"
else
    log_error "External DNS resolution failed"
fi

# Test Azure service DNS
if kubectl exec -n "$NAMESPACE" network-test -- nslookup management.azure.com &> /dev/null; then
    log_success "Azure service DNS resolution works (management.azure.com)"
else
    log_error "Azure service DNS resolution failed"
fi

# Test Kubernetes internal DNS
if kubectl exec -n "$NAMESPACE" network-test -- nslookup kubernetes.default.svc.cluster.local &> /dev/null; then
    log_success "Kubernetes internal DNS works (kubernetes.default.svc.cluster.local)"
else
    log_error "Kubernetes internal DNS failed"
fi

echo ""
log_info "=== Network Connectivity Tests ==="

# Test outbound HTTPS
if kubectl exec -n "$NAMESPACE" network-test -- curl -s -o /dev/null -w "%{http_code}" https://www.microsoft.com | grep -q "200\|301\|302"; then
    log_success "Outbound HTTPS connectivity works (https://www.microsoft.com)"
else
    log_error "Outbound HTTPS connectivity failed"
fi

# Test Azure API connectivity
if kubectl exec -n "$NAMESPACE" network-test -- curl -s -o /dev/null -w "%{http_code}" https://management.azure.com | grep -q "200\|401"; then
    log_success "Azure API connectivity works (https://management.azure.com)"
else
    log_error "Azure API connectivity failed"
fi

# Test MCR connectivity (Microsoft Container Registry)
if kubectl exec -n "$NAMESPACE" network-test -- curl -s -o /dev/null -w "%{http_code}" https://mcr.microsoft.com | grep -q "200\|301\|302"; then
    log_success "MCR connectivity works (https://mcr.microsoft.com)"
else
    log_error "MCR connectivity failed"
fi

echo ""
log_info "=== Pod Network Information ==="

# Get pod IP
POD_IP=$(kubectl get pod network-test -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
log_info "Pod IP: $POD_IP"

# Get node IP
NODE_IP=$(kubectl get pod network-test -n "$NAMESPACE" -o jsonpath='{.status.hostIP}')
log_info "Node IP: $NODE_IP"

# Check if IP is from expected overlay CIDR (192.168.0.0/16)
if [[ $POD_IP == 192.168.* ]]; then
    log_success "Pod IP is from overlay CIDR (192.168.0.0/16)"
else
    log_error "Pod IP is not from expected overlay CIDR (got $POD_IP, expected 192.168.x.x)"
fi

echo ""
log_info "=== Cleanup ==="

# Delete test resources
kubectl delete namespace "$NAMESPACE" --wait=false > /dev/null
log_success "Test namespace deleted"

echo ""
log_info "=== Validation Summary ==="
echo -e "${GREEN}Passed:${NC} $PASSED"
echo -e "${RED}Failed:${NC} $FAILED"

if [ $FAILED -eq 0 ]; then
    log_success "Network validation completed successfully!"
    exit 0
else
    log_error "Network validation completed with $FAILED error(s)"
    exit 1
fi
