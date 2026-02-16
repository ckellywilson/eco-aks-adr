#!/usr/bin/env bash
# =============================================================================
# ADO Pipeline Setup Script
# =============================================================================
# Automates the one-time setup of an Azure DevOps pipeline for Terraform
# deployments using Workload Identity Federation (OIDC).
#
# What this script does:
#   1. Creates an Azure AD App Registration + Service Principal
#   2. Grants RBAC roles (Contributor + Storage Blob Data Contributor,
#      plus User Access Administrator for spoke pipelines)
#   3. Creates an ADO service connection (Workload Identity Federation)
#   4. Creates a federated credential on the App Registration
#   5. Grants all pipelines access to the service connection
#   6. Creates the pipeline definition (GitHub or ADO Git — auto-detected)
#   7. Creates platform RG + management Key Vault + SSH key pair
#   8. Sets the agent pool and pipeline variables (PLATFORM_KV_ID)
#
# Prerequisites:
#   - Azure CLI authenticated (`az login`)
#   - ADO PAT with Build (Read & Execute), Code (Read), Work Items (Read) scopes
#   - jq, ssh-keygen, and curl installed
#   - For GitHub repos: GitHub service connection in ADO project
#
# Usage:
#   export AZURE_DEVOPS_PAT='<your-pat>'
#   ./scripts/setup-ado-pipeline.sh
#
# Repository type is auto-detected from `git remote get-url origin`:
#   - github.com URLs → GitHub pipeline definition
#   - dev.azure.com / visualstudio.com URLs → ADO Git pipeline definition
#
# Reference: .github/instructions/ado-pipeline-setup.instructions.md
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — Customer must set these
# ---------------------------------------------------------------------------
ADO_ORG="${ADO_ORG:-}"
ADO_PROJECT="${ADO_PROJECT:-}"
REPO_URL="${REPO_URL:-}"                        # Auto-detected from git remote
AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-}"
AZURE_DEVOPS_PAT="${AZURE_DEVOPS_PAT:-}"
PIPELINE_YAML_PATH="${PIPELINE_YAML_PATH:-pipelines/hub-deploy.yml}"
SERVICE_CONNECTION_NAME="${SERVICE_CONNECTION_NAME:-azure-hub-prod}"
PIPELINE_NAME="${PIPELINE_NAME:-hub-deploy}"
LOCATION="${LOCATION:-eastus2}"
LOCATION_CODE="${LOCATION_CODE:-eus2}"
ENVIRONMENT="${ENVIRONMENT:-prod}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
fail()  { error "$@"; exit 1; }

ado_api() {
  local method="$1" url="$2" data="${3:-}"
  local args=(-s -w "\n%{http_code}" -u ":$AZURE_DEVOPS_PAT" -H "Content-Type: application/json")
  [[ "$method" == "POST" || "$method" == "PUT" ]] && args+=(-X "$method" -d "$data")
  [[ "$method" == "GET" ]] && args+=(-X GET)

  local result
  result=$(curl "${args[@]}" "$url")
  local http_code body
  http_code=$(echo "$result" | tail -1)
  body=$(echo "$result" | head -n -1)

  if [[ "$http_code" -ge 400 ]]; then
    error "API call failed (HTTP $http_code): $url"
    echo "$body" | jq '.' 2>/dev/null || echo "$body"
    return 1
  fi
  echo "$body"
}

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
preflight() {
  log "Running preflight checks..."

  command -v az    >/dev/null 2>&1 || fail "Azure CLI (az) not found. Install: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"
  command -v jq    >/dev/null 2>&1 || fail "jq not found. Install: sudo apt-get install jq"
  command -v curl  >/dev/null 2>&1 || fail "curl not found."
  command -v ssh-keygen >/dev/null 2>&1 || fail "ssh-keygen not found."

  # Prompt for missing required values
  if [[ -z "$ADO_ORG" ]]; then
    read -rp "Azure DevOps organization name (e.g. 'myorg'): " ADO_ORG
  fi
  if [[ -z "$ADO_PROJECT" ]]; then
    read -rp "Azure DevOps project name: " ADO_PROJECT
  fi

  # Auto-detect repository type and URL from git remote
  if [[ -z "$REPO_URL" ]]; then
    local detected_url
    detected_url=$(git remote get-url origin 2>/dev/null || true)
    if [[ -n "$detected_url" ]]; then
      read -rp "Repository URL [$detected_url]: " REPO_URL
      REPO_URL="${REPO_URL:-$detected_url}"
    else
      read -rp "Repository URL (GitHub or ADO Git): " REPO_URL
    fi
  fi

  # Determine repo type from URL
  if echo "$REPO_URL" | grep -qE '(dev\.azure\.com|visualstudio\.com)'; then
    REPO_TYPE="TfsGit"
    # Extract ADO Git repo name: last segment before .git or end
    REPO_NAME=$(echo "$REPO_URL" | sed -E 's|.*/_git/([^/]+)(\.git)?$|\1|')
    log "  Detected ADO Git repository: $REPO_NAME"
  elif echo "$REPO_URL" | grep -qE 'github\.com'; then
    REPO_TYPE="GitHub"
    # Extract owner/repo from GitHub URL
    REPO_NAME=$(echo "$REPO_URL" | sed -E 's|.*github\.com[:/](.+?)(\.git)?$|\1|')
    log "  Detected GitHub repository: $REPO_NAME"
  else
    fail "Cannot determine repository type from URL: $REPO_URL\nExpected GitHub (github.com) or ADO Git (dev.azure.com)"
  fi

  if [[ -z "$AZURE_SUBSCRIPTION_ID" ]]; then
    local detected_sub
    detected_sub=$(az account show --query id -o tsv 2>/dev/null || true)
    if [[ -n "$detected_sub" ]]; then
      read -rp "Azure subscription ID [$detected_sub]: " AZURE_SUBSCRIPTION_ID
      AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-$detected_sub}"
    else
      read -rp "Azure subscription ID: " AZURE_SUBSCRIPTION_ID
    fi
  fi
  if [[ -z "$AZURE_DEVOPS_PAT" ]]; then
    read -rsp "Azure DevOps PAT (hidden): " AZURE_DEVOPS_PAT
    echo
  fi

  [[ -z "$ADO_ORG" ]]              && fail "ADO_ORG is required"
  [[ -z "$ADO_PROJECT" ]]          && fail "ADO_PROJECT is required"
  [[ -z "$REPO_URL" ]]             && fail "REPO_URL is required"
  [[ -z "$AZURE_SUBSCRIPTION_ID" ]] && fail "AZURE_SUBSCRIPTION_ID is required"
  [[ -z "$AZURE_DEVOPS_PAT" ]]     && fail "AZURE_DEVOPS_PAT is required"

  # Verify Azure CLI auth
  az account show --query '{sub:name, id:id}' -o json >/dev/null 2>&1 || fail "Azure CLI not authenticated. Run: az login"

  # Verify ADO connectivity
  ado_api GET "https://dev.azure.com/$ADO_ORG/_apis/projects/$ADO_PROJECT?api-version=7.1" >/dev/null || fail "Cannot reach ADO project. Check org/project/PAT."

  log "Preflight checks passed."
  log "  ADO Org:         $ADO_ORG"
  log "  ADO Project:     $ADO_PROJECT"
  log "  Repo Type:       $REPO_TYPE"
  log "  Repo Name:       $REPO_NAME"
  log "  Subscription:    $AZURE_SUBSCRIPTION_ID"
  log "  Pipeline YAML:   $PIPELINE_YAML_PATH"
  log "  Service Conn:    $SERVICE_CONNECTION_NAME"
  log "  Pipeline Name:   $PIPELINE_NAME"
  echo
}

# ---------------------------------------------------------------------------
# Step 1: Create App Registration + Service Principal
# ---------------------------------------------------------------------------
create_app_registration() {
  log "Step 1: Creating App Registration '$SERVICE_CONNECTION_NAME'..."

  # Check if it already exists
  local existing
  existing=$(az ad app list --display-name "$SERVICE_CONNECTION_NAME" --query "[0].appId" -o tsv 2>/dev/null || true)
  if [[ -n "$existing" && "$existing" != "None" ]]; then
    warn "App Registration '$SERVICE_CONNECTION_NAME' already exists (appId: $existing). Reusing."
    APP_ID="$existing"
    APP_OBJECT_ID=$(az ad app show --id "$APP_ID" --query id -o tsv)
    SP_OBJECT_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv 2>/dev/null || true)
    if [[ -z "$SP_OBJECT_ID" ]]; then
      SP_OBJECT_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)
    fi
    return
  fi

  local app_json
  app_json=$(az ad app create --display-name "$SERVICE_CONNECTION_NAME" -o json)
  APP_ID=$(echo "$app_json" | jq -r '.appId')
  APP_OBJECT_ID=$(echo "$app_json" | jq -r '.id')

  local sp_json
  sp_json=$(az ad sp create --id "$APP_ID" -o json)
  SP_OBJECT_ID=$(echo "$sp_json" | jq -r '.id')

  log "  App ID:        $APP_ID"
  log "  SP Object ID:  $SP_OBJECT_ID"
}

# ---------------------------------------------------------------------------
# Step 2: Grant RBAC roles
# ---------------------------------------------------------------------------
grant_rbac() {
  log "Step 2: Granting RBAC roles..."

  local scope="/subscriptions/$AZURE_SUBSCRIPTION_ID"

  # Base roles for all pipelines (hub + spoke)
  local roles=("Contributor" "Storage Blob Data Contributor")

  # Spoke pipelines create azurerm_role_assignment resources (e.g., AKS UAMI → DNS zone,
  # kubelet → AcrPull, control plane → Key Vault). This requires
  # Microsoft.Authorization/roleAssignments/write, which Contributor does not include.
  if [[ "$PIPELINE_NAME" == *spoke* ]]; then
    roles+=("User Access Administrator")
    log "  Spoke pipeline detected — adding User Access Administrator role"
  fi

  for role in "${roles[@]}"; do
    local existing_role
    existing_role=$(az role assignment list --assignee "$SP_OBJECT_ID" --role "$role" --scope "$scope" --query "length(@)" -o tsv 2>/dev/null || echo "0")
    if [[ "$existing_role" -gt 0 ]]; then
      warn "  Role '$role' already assigned. Skipping."
    else
      az role assignment create \
        --assignee-object-id "$SP_OBJECT_ID" \
        --assignee-principal-type ServicePrincipal \
        --role "$role" \
        --scope "$scope" \
        -o none
      log "  Granted: $role"
    fi
  done
}

# ---------------------------------------------------------------------------
# Step 3: Create ADO service connection
# ---------------------------------------------------------------------------
create_service_connection() {
  log "Step 3: Creating ADO service connection..."

  local subscription_name tenant_id project_id
  subscription_name=$(az account show --query name -o tsv)
  tenant_id=$(az account show --query tenantId -o tsv)
  project_id=$(ado_api GET "https://dev.azure.com/$ADO_ORG/_apis/projects/$ADO_PROJECT?api-version=7.1" | jq -r '.id')

  # Check if service connection already exists
  local existing_sc
  existing_sc=$(ado_api GET "https://dev.azure.com/$ADO_ORG/$ADO_PROJECT/_apis/serviceendpoint/endpoints?api-version=7.1" | \
    jq -r --arg name "$SERVICE_CONNECTION_NAME" '.value[] | select(.name == $name) | .id')

  if [[ -n "$existing_sc" ]]; then
    warn "Service connection '$SERVICE_CONNECTION_NAME' already exists (id: $existing_sc). Reusing."
    ENDPOINT_ID="$existing_sc"
    return
  fi

  local payload
  payload=$(jq -n \
    --arg subId "$AZURE_SUBSCRIPTION_ID" \
    --arg subName "$subscription_name" \
    --arg tenantId "$tenant_id" \
    --arg appId "$APP_ID" \
    --arg scName "$SERVICE_CONNECTION_NAME" \
    --arg projId "$project_id" \
    --arg projName "$ADO_PROJECT" \
    '{
      data: {
        subscriptionId: $subId,
        subscriptionName: $subName,
        environment: "AzureCloud",
        scopeLevel: "Subscription",
        creationMode: "Manual"
      },
      name: $scName,
      type: "AzureRM",
      url: "https://management.azure.com/",
      authorization: {
        parameters: {
          tenantid: $tenantId,
          serviceprincipalid: $appId
        },
        scheme: "WorkloadIdentityFederation"
      },
      isShared: false,
      isReady: true,
      serviceEndpointProjectReferences: [{
        projectReference: { id: $projId, name: $projName },
        name: $scName
      }]
    }')

  local result
  result=$(ado_api POST "https://dev.azure.com/$ADO_ORG/_apis/serviceendpoint/endpoints?api-version=7.1" "$payload")
  ENDPOINT_ID=$(echo "$result" | jq -r '.id')

  [[ -z "$ENDPOINT_ID" || "$ENDPOINT_ID" == "null" ]] && fail "Failed to create service connection"
  log "  Endpoint ID: $ENDPOINT_ID"
}

# ---------------------------------------------------------------------------
# Step 4: Create federated credential
# ---------------------------------------------------------------------------
create_federated_credential() {
  log "Step 4: Creating federated credential..."

  # Get issuer and subject from the service connection
  local endpoint_detail issuer subject
  endpoint_detail=$(ado_api GET "https://dev.azure.com/$ADO_ORG/$ADO_PROJECT/_apis/serviceendpoint/endpoints/$ENDPOINT_ID?api-version=7.1")
  issuer=$(echo "$endpoint_detail" | jq -r '.authorization.parameters.workloadIdentityFederationIssuer')
  subject=$(echo "$endpoint_detail" | jq -r '.authorization.parameters.workloadIdentityFederationSubject')

  [[ -z "$issuer" || "$issuer" == "null" ]] && fail "Could not retrieve federation issuer from service connection"

  # Check if federated credential already exists
  local existing_cred
  existing_cred=$(az ad app federated-credential list --id "$APP_OBJECT_ID" --query "[?name=='ado-${ADO_PROJECT}-${PIPELINE_NAME}'].name" -o tsv 2>/dev/null || true)
  if [[ -n "$existing_cred" ]]; then
    warn "Federated credential already exists. Skipping."
    return
  fi

  az ad app federated-credential create \
    --id "$APP_OBJECT_ID" \
    --parameters "{
      \"name\": \"ado-${ADO_PROJECT}-${PIPELINE_NAME}\",
      \"issuer\": \"$issuer\",
      \"subject\": \"$subject\",
      \"audiences\": [\"api://AzureADTokenExchange\"],
      \"description\": \"ADO pipeline federated credential for $PIPELINE_NAME\"
    }" \
    -o none

  log "  Federated credential created."
}

# ---------------------------------------------------------------------------
# Step 5: Grant pipeline access to service connection
# ---------------------------------------------------------------------------
grant_pipeline_access() {
  log "Step 5: Granting pipeline access to service connection..."

  ado_api PATCH \
    "https://dev.azure.com/$ADO_ORG/$ADO_PROJECT/_apis/pipelines/pipelinepermissions?api-version=7.1-preview.1" \
    "[{
      \"resource\": { \"id\": \"$ENDPOINT_ID\", \"type\": \"endpoint\" },
      \"allPipelines\": { \"authorized\": true },
      \"pipelines\": []
    }]" >/dev/null

  log "  All pipelines authorized."
}

# ---------------------------------------------------------------------------
# Step 6: Create pipeline definition
# ---------------------------------------------------------------------------
create_pipeline() {
  log "Step 6: Creating pipeline definition..."

  # Check if pipeline already exists
  local existing_pipeline
  existing_pipeline=$(ado_api GET "https://dev.azure.com/$ADO_ORG/$ADO_PROJECT/_apis/build/definitions?api-version=7.1&name=$PIPELINE_NAME" | \
    jq -r '.value[0].id // empty')

  if [[ -n "$existing_pipeline" ]]; then
    warn "Pipeline '$PIPELINE_NAME' already exists (id: $existing_pipeline). Reusing."
    PIPELINE_ID="$existing_pipeline"
    return
  fi

  local payload

  if [[ "$REPO_TYPE" == "GitHub" ]]; then
    # Find GitHub service connection
    local gh_sc_id
    gh_sc_id=$(ado_api GET "https://dev.azure.com/$ADO_ORG/$ADO_PROJECT/_apis/serviceendpoint/endpoints?api-version=7.1" | \
      jq -r '.value[] | select(.type == "GitHub") | .id' | head -1)

    [[ -z "$gh_sc_id" || "$gh_sc_id" == "null" ]] && fail "No GitHub service connection found in ADO project. Create one first: Project Settings → Service connections → New → GitHub"

    payload=$(jq -n \
      --arg name "$PIPELINE_NAME" \
      --arg yaml "$PIPELINE_YAML_PATH" \
      --arg repo "$REPO_NAME" \
      --arg ghScId "$gh_sc_id" \
      '{
        name: $name,
        type: "build",
        quality: "definition",
        process: { yamlFilename: $yaml, type: 2 },
        repository: {
          id: $repo,
          name: $repo,
          type: "GitHub",
          defaultBranch: "refs/heads/main",
          properties: {
            connectedServiceId: $ghScId,
            apiUrl: ("https://api.github.com/repos/" + $repo),
            branchesUrl: ("https://api.github.com/repos/" + $repo + "/branches"),
            cloneUrl: ("https://github.com/" + $repo + ".git"),
            refsUrl: ("https://api.github.com/repos/" + $repo + "/git/refs")
          },
          url: ("https://github.com/" + $repo + ".git")
        },
        triggers: [{ settingsSourceType: 2, triggerType: "continuousIntegration" }]
      }')

  elif [[ "$REPO_TYPE" == "TfsGit" ]]; then
    # For ADO Git, get repository ID from the project
    local ado_repo_id
    ado_repo_id=$(ado_api GET "https://dev.azure.com/$ADO_ORG/$ADO_PROJECT/_apis/git/repositories/$REPO_NAME?api-version=7.1" | \
      jq -r '.id // empty')

    [[ -z "$ado_repo_id" || "$ado_repo_id" == "null" ]] && fail "ADO Git repository '$REPO_NAME' not found in project '$ADO_PROJECT'"

    payload=$(jq -n \
      --arg name "$PIPELINE_NAME" \
      --arg yaml "$PIPELINE_YAML_PATH" \
      --arg repoId "$ado_repo_id" \
      --arg repoName "$REPO_NAME" \
      '{
        name: $name,
        type: "build",
        quality: "definition",
        process: { yamlFilename: $yaml, type: 2 },
        repository: {
          id: $repoId,
          name: $repoName,
          type: "TfsGit",
          defaultBranch: "refs/heads/main",
          url: ("https://dev.azure.com/" + env.ADO_ORG + "/" + env.ADO_PROJECT + "/_git/" + $repoName)
        },
        triggers: [{ settingsSourceType: 2, triggerType: "continuousIntegration" }]
      }')
  fi

  local result
  result=$(ado_api POST "https://dev.azure.com/$ADO_ORG/$ADO_PROJECT/_apis/build/definitions?api-version=7.1" "$payload")
  PIPELINE_ID=$(echo "$result" | jq -r '.id')

  [[ -z "$PIPELINE_ID" || "$PIPELINE_ID" == "null" ]] && fail "Failed to create pipeline"

  log "  Pipeline ID: $PIPELINE_ID"
}

# ---------------------------------------------------------------------------
# Step 7: Set agent pool and pipeline variables
# ---------------------------------------------------------------------------
configure_pipeline() {
  log "Step 7: Configuring pipeline pool and variables..."

  # Find the Azure Pipelines queue ID (project-scoped)
  local queue_id
  queue_id=$(ado_api GET "https://dev.azure.com/$ADO_ORG/$ADO_PROJECT/_apis/distributedtask/queues?api-version=7.1" | \
    jq -r '.value[] | select(.name == "Azure Pipelines") | .id')

  [[ -z "$queue_id" || "$queue_id" == "null" ]] && fail "Azure Pipelines hosted pool not found"

  # Get current definition and update
  local definition updated
  definition=$(ado_api GET "https://dev.azure.com/$ADO_ORG/$ADO_PROJECT/_apis/build/definitions/$PIPELINE_ID?api-version=7.1")

  # Set pool
  updated=$(echo "$definition" | jq --arg qid "$queue_id" '.queue = {"id": ($qid | tonumber), "name": "Azure Pipelines"}')

  # Set PLATFORM_KV_ID variable if platform KV was created
  if [[ -n "${PLATFORM_KV_ID:-}" ]]; then
    updated=$(echo "$updated" | jq --arg kvId "$PLATFORM_KV_ID" '.variables.PLATFORM_KV_ID = {"value": $kvId, "isSecret": false, "allowOverride": true}')
    log "  Pipeline variable PLATFORM_KV_ID set."
  else
    warn "  PLATFORM_KV_ID not available. Set it manually in pipeline variables after creating platform KV."
  fi

  ado_api PUT "https://dev.azure.com/$ADO_ORG/$ADO_PROJECT/_apis/build/definitions/$PIPELINE_ID?api-version=7.1" "$updated" >/dev/null

  log "  Pool: Azure Pipelines (queue $queue_id)"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Step 8: Create platform resource group + management Key Vault + SSH keys
# ---------------------------------------------------------------------------
create_platform_kv() {
  log "Step 8: Creating platform resource group and Key Vault..."

  local platform_rg="rg-platform-${LOCATION_CODE}-${ENVIRONMENT}"
  local kv_suffix
  kv_suffix=$(echo "$AZURE_SUBSCRIPTION_ID" | md5sum | cut -c1-8)
  local kv_name="kv-platform-${LOCATION_CODE}-${kv_suffix}"

  # Create platform resource group
  if az group show -n "$platform_rg" &> /dev/null; then
    warn "Platform resource group '$platform_rg' already exists. Reusing."
  else
    az group create -n "$platform_rg" -l "$LOCATION" -o none
    log "  Created resource group: $platform_rg"
  fi

  # Create Key Vault
  if az keyvault show -n "$kv_name" &> /dev/null 2>&1; then
    warn "Key Vault '$kv_name' already exists. Reusing."
  else
    az keyvault create \
      -n "$kv_name" \
      -g "$platform_rg" \
      -l "$LOCATION" \
      --enable-rbac-authorization true \
      --enable-purge-protection true \
      --retention-days 7 \
      -o none
    log "  Created Key Vault: $kv_name"
  fi

  PLATFORM_KV_ID=$(az keyvault show -n "$kv_name" --query id -o tsv)

  # Grant current user Key Vault Administrator to set secrets
  local current_user_oid
  current_user_oid=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)
  if [[ -n "$current_user_oid" ]]; then
    local existing_role
    existing_role=$(az role assignment list --assignee "$current_user_oid" --role "Key Vault Administrator" --scope "$PLATFORM_KV_ID" --query "length(@)" -o tsv 2>/dev/null || echo "0")
    if [[ "$existing_role" -eq 0 ]]; then
      az role assignment create \
        --assignee-object-id "$current_user_oid" \
        --assignee-principal-type User \
        --role "Key Vault Administrator" \
        --scope "$PLATFORM_KV_ID" \
        -o none
      log "  Granted Key Vault Administrator to current user"
      log "  Waiting 30s for RBAC propagation..."
      sleep 30
    fi
  fi

  # Grant service principal Key Vault Secrets User (for Terraform to read SSH key)
  if [[ -n "${SP_OBJECT_ID:-}" ]]; then
    local existing_sp_role
    existing_sp_role=$(az role assignment list --assignee "$SP_OBJECT_ID" --role "Key Vault Secrets User" --scope "$PLATFORM_KV_ID" --query "length(@)" -o tsv 2>/dev/null || echo "0")
    if [[ "$existing_sp_role" -eq 0 ]]; then
      az role assignment create \
        --assignee-object-id "$SP_OBJECT_ID" \
        --assignee-principal-type ServicePrincipal \
        --role "Key Vault Secrets User" \
        --scope "$PLATFORM_KV_ID" \
        -o none
      log "  Granted Key Vault Secrets User to pipeline service principal"
    fi
  fi

  # Generate SSH key pair and store in KV
  local existing_secret
  existing_secret=$(az keyvault secret show --vault-name "$kv_name" -n "ssh-public-key" --query "value" -o tsv 2>/dev/null || true)
  if [[ -n "$existing_secret" ]]; then
    warn "SSH key already exists in Key Vault. Skipping generation."
  else
    local tmpdir
    tmpdir=$(mktemp -d)
    ssh-keygen -t ed25519 -f "$tmpdir/ssh-key" -N "" -C "aks-landing-zone-${ENVIRONMENT}" > /dev/null 2>&1

    az keyvault secret set --vault-name "$kv_name" -n "ssh-public-key" --value "$(cat "$tmpdir/ssh-key.pub")" -o none
    az keyvault secret set --vault-name "$kv_name" -n "ssh-private-key" --value "$(cat "$tmpdir/ssh-key")" -o none

    rm -rf "$tmpdir"
    log "  Generated SSH key pair and stored in Key Vault"
  fi

  log "  Platform KV ID: $PLATFORM_KV_ID"
}

main() {
  echo "============================================="
  echo "  ADO Pipeline Setup — Workload Identity"
  echo "============================================="
  echo

  preflight
  create_app_registration
  grant_rbac
  create_service_connection
  create_federated_credential
  grant_pipeline_access
  create_pipeline
  create_platform_kv
  configure_pipeline

  echo
  log "============================================="
  log "  Setup complete!"
  log "============================================="
  log ""
  log "  Pipeline:      https://dev.azure.com/$ADO_ORG/$ADO_PROJECT/_build?definitionId=$PIPELINE_ID"
  log "  Service Conn:  $SERVICE_CONNECTION_NAME (Workload Identity Federation)"
  log "  App Reg:       $APP_ID"
  log "  Repo Type:     $REPO_TYPE"
  log "  Platform KV:   $PLATFORM_KV_ID"
  log ""
  log "  PLATFORM_KV_ID has been set as a pipeline variable."
  log "  To trigger: push to main or run manually in ADO"
  log ""
  log "  After first hub deploy with deploy_cicd_agents=true:"
  log "    1. Register the ACI UAMI as a service principal in your ADO org"
  log "    2. Grant it Admin access on the agent pool"
  log "    3. Switch pipeline pool from 'Azure Pipelines' to self-hosted pool"
}

main "$@"
