#!/bin/bash
# Verification script for AKS Private DNS configuration
# Run this if the cluster deployment fails to verify DNS zone configuration

set -e

echo "=== AKS Private DNS Configuration Verification ==="
echo ""

# Check location variable
echo "1. Checking location variable from prod.tfvars:"
LOCATION=$(grep "^location " prod.tfvars | awk '{print $3}' | tr -d '"')
echo "   Location: $LOCATION"
EXPECTED_ZONE="privatelink.${LOCATION}.azmk8s.io"
echo "   Expected DNS Zone: $EXPECTED_ZONE"
echo ""

# Check if private DNS zone exists in hub
echo "2. Checking if private DNS zone exists in hub:"
az network private-dns zone show \
  --resource-group rg-hub-eus2-prod \
  --name "$EXPECTED_ZONE" \
  --query "{Name:name, ResourceGroup:resourceGroup, NumberOfRecordSets:numberOfRecordSets}" \
  --output table
echo ""

# Check VNet links
echo "3. Checking VNet links to private DNS zone:"
echo "   Hub VNet link:"
az network private-dns link vnet list \
  --resource-group rg-hub-eus2-prod \
  --zone-name "$EXPECTED_ZONE" \
  --query "[?contains(name, 'hub')].{Name:name, VNetId:virtualNetwork.id, RegistrationEnabled:registrationEnabled}" \
  --output table
echo ""
echo "   Spoke VNet link:"
az network private-dns link vnet list \
  --resource-group rg-hub-eus2-prod \
  --zone-name "$EXPECTED_ZONE" \
  --query "[?contains(name, 'spoke')].{Name:name, VNetId:virtualNetwork.id, RegistrationEnabled:registrationEnabled}" \
  --output table
echo ""

# Check A records
echo "4. Checking A records in private DNS zone:"
RECORD_COUNT=$(az network private-dns record-set a list \
  --resource-group rg-hub-eus2-prod \
  --zone-name "$EXPECTED_ZONE" \
  --query "length(@)")
echo "   Total A records: $RECORD_COUNT"

if [ "$RECORD_COUNT" -gt 0 ]; then
  echo "   A records:"
  az network private-dns record-set a list \
    --resource-group rg-hub-eus2-prod \
    --zone-name "$EXPECTED_ZONE" \
    --query "[].{Name:name, FQDN:fqdn, IP:aRecords[0].ipv4Address, TTL:ttl}" \
    --output table
else
  echo "   ⚠️  NO A RECORDS FOUND - This indicates the private endpoint A record was not created"
fi
echo ""

# Check RBAC permissions
echo "5. Checking RBAC role assignments on private DNS zone:"
UAMI_NAME="uami-aks-cp-prod-eus2"
UAMI_PRINCIPAL_ID=$(az identity show \
  --resource-group rg-aks-eus2-prod \
  --name "$UAMI_NAME" \
  --query principalId \
  --output tsv 2>/dev/null || echo "NOT_FOUND")

if [ "$UAMI_PRINCIPAL_ID" != "NOT_FOUND" ]; then
  echo "   AKS Control Plane Identity: $UAMI_NAME"
  echo "   Principal ID: $UAMI_PRINCIPAL_ID"
  echo ""
  echo "   Role assignments on DNS zone:"
  DNS_ZONE_ID="/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-hub-eus2-prod/providers/Microsoft.Network/privateDnsZones/$EXPECTED_ZONE"
  az role assignment list \
    --scope "$DNS_ZONE_ID" \
    --assignee "$UAMI_PRINCIPAL_ID" \
    --query "[].{Role:roleDefinitionName, Scope:scope}" \
    --output table
else
  echo "   ⚠️  AKS Control Plane Identity not found"
fi
echo ""

# Check spoke VNet custom DNS
echo "6. Checking spoke VNet custom DNS configuration:"
az network vnet show \
  --resource-group rg-aks-eus2-prod \
  --name vnet-aks-prod-eus2 \
  --query "{Name:name, DnsServers:dhcpOptions.dnsServers}" \
  --output table
echo ""

echo "=== Verification Complete ==="
echo ""
echo "Expected configuration:"
echo "  - Private DNS Zone: $EXPECTED_ZONE"
echo "  - Hub VNet linked: YES"
echo "  - Spoke VNet linked: YES"
echo "  - AKS Control Plane Identity: Has 'Private DNS Zone Contributor' role"
echo "  - Spoke VNet DNS: Points to hub DNS resolver inbound endpoint"
echo "  - A record for AKS API server: Should exist after cluster creation"
