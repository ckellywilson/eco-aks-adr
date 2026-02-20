#!/usr/bin/env bash
#
# Terraform Destroy with Recovery
# 
# Description: Semi-automated Terraform destroy with pre-flight checks and error recovery
# Usage: Run from within a Terraform module directory
#        cd infra/terraform/<module>
#        ../../scripts/destroy-with-recovery.sh
#

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Logging
readonly LOG_DIR="."
readonly LOG_FILE="${LOG_DIR}/destroy-$(date +%Y%m%d-%H%M%S).log"

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "${LOG_FILE}"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" | tee -a "${LOG_FILE}"
}

# Pre-flight checks
check_azure_auth() {
    log "Checking Azure authentication..."
    
    if ! az account show &>/dev/null; then
        log_error "Not logged into Azure CLI"
        echo ""
        echo "Please run: az login"
        return 1
    fi
    
    local subscription_name
    subscription_name=$(az account show --query name -o tsv)
    local subscription_id
    subscription_id=$(az account show --query id -o tsv)
    
    log "Authenticated to Azure subscription:"
    echo "  Name: ${subscription_name}"
    echo "  ID: ${subscription_id}"
    echo ""
    
    read -p "Is this the correct subscription? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_error "User aborted - incorrect subscription"
        echo "Run 'az account set --subscription <subscription-id>' to change"
        return 1
    fi
    
    return 0
}

validate_backend_exists() {
    log "Validating backend configuration..."
    
    if [[ ! -f "backend-prod.tfbackend" ]]; then
        log_error "Backend config file not found: backend-prod.tfbackend"
        return 1
    fi
    
    log "Backend config file found: backend-prod.tfbackend"
    
    # Extract backend details for validation
    if grep -q "resource_group_name" backend-prod.tfbackend; then
        local rg_name
        rg_name=$(grep "resource_group_name" backend-prod.tfbackend | cut -d'=' -f2 | tr -d ' "')
        log "Backend resource group: ${rg_name}"
        
        if az group show --name "${rg_name}" &>/dev/null; then
            log "Backend resource group exists"
        else
            log_warn "Backend resource group not found - may cause issues"
        fi
    fi
    
    return 0
}

sync_terraform_state() {
    log "Initializing Terraform with backend..."
    
    if ! terraform init -backend-config=backend-prod.tfbackend -reconfigure; then
        log_error "Terraform init failed"
        return 1
    fi
    
    log "Checking for state drift..."
    
    if terraform plan -detailed-exitcode -out=tfplan.destroy-check &>/dev/null; then
        log "State is synchronized (no drift detected)"
        rm -f tfplan.destroy-check
    else
        local exit_code=$?
        if [[ $exit_code -eq 2 ]]; then
            log_warn "State drift detected - there are pending changes"
            echo ""
            echo "This usually means:"
            echo "  1. Resources have been modified outside Terraform"
            echo "  2. Configuration changes haven't been applied"
            echo ""
            read -p "Continue with destroy despite drift? (yes/no): " -r
            if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                log_error "User aborted due to state drift"
                return 1
            fi
        else
            log_error "Terraform plan failed (exit code: ${exit_code})"
            return 1
        fi
    fi
    
    return 0
}

generate_destroy_plan() {
    log "Generating destroy plan..."
    
    if ! terraform plan -destroy -out=tfplan.destroy; then
        log_error "Failed to generate destroy plan"
        return 1
    fi
    
    log "Destroy plan generated: tfplan.destroy"
    echo ""
    log "Review the resources that will be destroyed above."
    echo ""
    
    return 0
}

execute_destroy() {
    log "Executing terraform destroy..."
    
    read -p "Type 'yes' to confirm destruction: " -r
    if [[ $REPLY != "yes" ]]; then
        log_error "User aborted - confirmation not received"
        rm -f tfplan.destroy
        return 1
    fi
    
    echo ""
    
    # Execute with explicit approval
    if terraform apply tfplan.destroy; then
        log "Destroy completed successfully"
        rm -f tfplan.destroy
        return 0
    else
        local exit_code=$?
        log_error "Destroy failed with exit code: ${exit_code}"
        
        # Capture last error from log
        echo ""
        log_error "Check the output above for error details"
        echo ""
        echo "Common recovery actions:"
        echo "  1. Retry destroy: terraform destroy"
        echo "  2. Targeted destroy: terraform destroy -target=<resource>"
        echo "  3. Check Azure Portal for stuck resources"
        echo "  4. Review: .github/instructions/terraform-destroy.instructions.md"
        echo ""
        echo "Error log saved to: ${LOG_FILE}"
        
        return 1
    fi
}

verify_cleanup() {
    log "Verifying cleanup..."
    
    local resource_count
    resource_count=$(terraform state list 2>/dev/null | wc -l)
    
    if [[ $resource_count -eq 0 ]]; then
        log "Success: All resources destroyed (state is empty)"
        return 0
    else
        log_warn "Warning: ${resource_count} resources still in state"
        echo ""
        echo "Remaining resources:"
        terraform state list
        echo ""
        log_warn "Some resources may not have been destroyed"
        return 1
    fi
}

main() {
    local module_name
    module_name=$(basename "$(pwd)")
    
    echo ""
    log "=== Terraform Destroy with Recovery ==="
    log "Module: ${module_name}"
    log "Working directory: $(pwd)"
    log "Log file: ${LOG_FILE}"
    echo ""
    
    # Pre-flight checks
    if ! check_azure_auth; then
        exit 1
    fi
    
    if ! validate_backend_exists; then
        exit 1
    fi
    
    if ! sync_terraform_state; then
        exit 1
    fi
    
    # Generate and review destroy plan
    if ! generate_destroy_plan; then
        exit 1
    fi
    
    # Execute destroy
    if ! execute_destroy; then
        exit 1
    fi
    
    # Verify cleanup
    verify_cleanup
    
    echo ""
    log "=== Destroy workflow completed ==="
    log "Log file: ${LOG_FILE}"
    echo ""
}

# Run main function
main "$@"
