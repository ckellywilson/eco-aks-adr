---
description: 'Terraform destroy workflow with pre-flight checks and error recovery'
applyTo: '**/*.tf'
---

# Terraform Destroy Workflow

This file provides guidance for safely destroying Terraform infrastructure with automated error recovery.

## Pre-Flight Checklist

Before running `terraform destroy`, ALWAYS complete these checks:

1. **Verify Azure Authentication**
   ```bash
   az account show
   ```
   - Confirm you're logged into the correct Azure subscription
   - Verify you have sufficient permissions to destroy resources
   - **CRITICAL**: Ensure you're in the subscription containing the infrastructure AND the backend storage

2. **Switch to Correct Subscription (If Needed)**
   ```bash
   # If backend storage is in different subscription
   az account set --subscription <backend-subscription-id>
   
   # Verify
   az account show --query '{Subscription:name, SubscriptionId:id}' -o table
   ```

3. **Enable Backend Storage Access (If Read-Only)**
   ```bash
   # Check backend configuration
   grep -E "(storage_account_name|resource_group_name)" backend-prod.tfbackend
   
   # Enable public network access on storage account
   az storage account update \
     --name <storage-account-name> \
     --resource-group <resource-group-name> \
     --public-network-access Enabled
   ```
   - Required if storage account has `publicNetworkAccess: Disabled`
   - Terraform backend needs access to state files
   - Can disable again after destroy completes

4. **Validate Backend Resources Exist**
   - Check that resources referenced in `*.tfbackend` files exist
   - Verify state file is accessible in Azure Storage
   - Confirm state lock mechanism is working

3. **Sync State with Infrastructure**
   ```bash
   terraform plan
   ```
   - Should show "No changes" if state is synchronized
   - If drift detected, investigate before destroying
   - Never destroy with unsynchronized state

**Note**: The destroy wrapper script (`infra/scripts/destroy-with-recovery.sh`) automates checks 4-5, but NOT subscription switching or storage account access (checks 2-3).

## Destroy Workflow

### Dependency Order (CRITICAL)

**ALWAYS destroy in this order:**

1. **Spoke deployments FIRST** (e.g., `spoke-aks-prod`)
   - AKS clusters
   - Spoke VNets with peering to hub
   - Application resources

2. **Hub deployments LAST** (e.g., `hub-eastus`)
   - Hub VNet
   - Azure Firewall
   - VPN Gateway
   - Shared services

**Reason**: Spoke resources often depend on hub infrastructure (VNet peering, firewall rules, DNS). Destroying hub first causes dependency errors.

### Using the Wrapper Script

**Recommended approach:**
```bash
cd infra/terraform/spoke-aks-prod
../../scripts/destroy-with-recovery.sh
```

The script automates:
- Pre-flight checks
- Backend initialization
- Destroy plan generation
- User confirmation prompts
- Error capture and recovery suggestions

### Manual Destroy (Not Recommended)

If you must run terraform directly:
```bash
terraform init -backend-config=backend-prod.tfbackend
terraform plan -destroy
terraform destroy
```

## Common Error Recovery Patterns

### 1. Dependency Errors

**Error**: "Cannot destroy resource X because resource Y depends on it"

**Recovery**:
```bash
# Option A: Targeted destroy of dependent resource first
terraform destroy -target=azurerm_resource_type.dependent_resource
terraform destroy  # Then destroy remaining

# Option B: Remove dependency in code, apply, then destroy
# Edit .tf files to remove dependency
terraform apply
terraform destroy
```

### 2. Timeout Errors

**Error**: "Error waiting for resource to be deleted" or timeout messages

**Recovery**:
```bash
# Wait 2-5 minutes, then retry
terraform destroy

# If persistent, check Azure Portal for resource status
# Resource may be stuck in provisioning/deleting state
# May require manual intervention via Portal
```

### 3. State Lock Errors

**Error**: "Error acquiring state lock"

**Recovery**:
```bash
# Check if another operation is running
# Wait for operation to complete

# If lock is orphaned (process died):
terraform force-unlock <LOCK_ID>
# CAUTION: Only use if you're certain no other operation is running
```

### 4. Resource Not Found (Already Deleted)

**Error**: "Resource not found" during destroy

**Recovery**:
```bash
# Remove from state (resource already gone from Azure)
terraform state rm <resource_address>

# Then continue destroy
terraform destroy
```

### 5. Permission Denied

**Error**: "Authorization failed" or "Insufficient permissions"

**Recovery**:
```bash
# Verify authentication
az account show
az login --tenant <tenant-id>

# Check RBAC permissions in Azure Portal
# Ensure you have Contributor or Owner role on resources
```

### 6. Orphaned Resources

**Scenario**: Terraform destroy completes but resources remain in Azure

**AKS-Specific Considerations:**
- **Private DNS A Records**: AKS control plane identity auto-creates A records in the private DNS zone. These should auto-delete when cluster is destroyed, but verify.
- **Check for orphaned resources**:
  ```bash
  # Check if private DNS A records remain
  az network private-dns record-set a list \
    --resource-group <hub-rg> \
    --zone-name privatelink.<region>.azmk8s.io
  
  # Check if peerings remain
  az network vnet peering list \
    --resource-group <hub-rg> \
    --vnet-name <hub-vnet>
  ```

**Recovery**:
```bash
# List remaining resources in state
terraform state list

# Check Azure Portal for orphaned resources
# Manually delete via Portal or CLI if necessary

# Clean up state
terraform state rm <orphaned_resource>
```

## Validation After Destroy

After successful destroy, verify:

```bash
# State should be empty
terraform state list
# Expected output: (empty)

# Backend state file should show no resources
# Check Azure Storage blob for state file
```

## Best Practices

1. **Always review destroy plan** before confirming
2. **Destroy during low-traffic periods** if production
3. **Take state file backups** before major operations
4. **Document any manual interventions** in destroy logs
5. **Check Azure Portal** after destroy to confirm cleanup
6. **Use wrapper script** for consistent, repeatable destroys
7. **Test destroy workflow** in dev/test environments first

## Script Reference

**Wrapper script location**: `infra/scripts/destroy-with-recovery.sh`

**Features**:
- Automated pre-flight checks
- Structured error logging
- Recovery suggestions on failure
- Timestamp-based log files

**Usage**:
```bash
cd infra/terraform/<module-name>
../../scripts/destroy-with-recovery.sh
```

## Emergency Procedures

If destroy is critically failing:

1. **Stop immediately** - Don't force through errors
2. **Capture error output** - Save logs for troubleshooting
3. **Check Azure Portal** - Verify actual resource state
4. **Review state file** - Understand what Terraform thinks exists
5. **Consult this guide** - Match error to recovery pattern
6. **Escalate if needed** - Get help rather than risk data loss

## Related Documentation

- Repository workflow: `.github/copilot-instructions.md`
- Terraform modules: `infra/terraform/*/README.md`
- Azure backend config: `*.tfbackend.example` files
