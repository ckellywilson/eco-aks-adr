#!/usr/bin/env bash
# =============================================================================
# ADO Pipeline Setup Script
# =============================================================================
# Automates the one-time setup of an Azure DevOps pipeline for Terraform
# deployments using Workload Identity Federation (OIDC).
#
# What this script does:
#   1. Creates an Azure AD App Registration + Service Principal
#   2. Grants RBAC roles (Contributor + Storage Blob Data Contributor)
#   3. Creates an ADO service connection (Workload Identity Federation)
#   4. Creates a federated credential on the App Registration
#   5. Grants all pipelines access to the service connection
#   6. Creates the pipeline definition pointing to the GitHub repo
#   7. Sets the agent pool and pipeline secret variable
#
# Prerequisites:
#   - Azure CLI authenticated (`az login`)
#   - ADO PAT with Build (Read & Execute), Code (Read), Work Items (Read) scopes
#   - jq installed
#
# Usage:
#   export AZURE_DEVOPS_PAT='<your-pat>'
#   ./scripts/setup-ado-pipeline.sh
#
# Reference: .github/instructions/ado-pipeline-setup.instructions.md
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — Customer must set these
# ---------------------------------------------------------------------------
ADO_ORG="${ADO_ORG:-}"
ADO_PROJECT="${ADO_PROJECT:-}"
GITHUB_REPO="${GITHUB_REPO:-}"                  # e.g. "owner/repo"
AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-}"
AZURE_DEVOPS_PAT="${AZURE_DEVOPS_PAT:-}"
PIPELINE_YAML_PATH="${PIPELINE_YAML_PATH:-pipelines/hub-deploy.yml}"
SERVICE_CONNECTION_NAME="${SERVICE_CONNECTION_NAME:-azure-hub-prod}"
PIPELINE_NAME="${PIPELINE_NAME:-hub-deploy}"
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:-}"              # Optional: set pipeline secret

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

  # Prompt for missing required values
  if [[ -z "$ADO_ORG" ]]; then
    read -rp "Azure DevOps organization name (e.g. 'myorg'): " ADO_ORG
  fi
  if [[ -z "$ADO_PROJECT" ]]; then
    read -rp "Azure DevOps project name: " ADO_PROJECT
  fi
  if [[ -z "$GITHUB_REPO" ]]; then
    # Try to detect from git remote
    local detected
    detected=$(git remote get-url origin 2>/dev/null | sed -E 's|.*github\.com[:/](.+)\.git$|\1|' || true)
    if [[ -n "$detected" ]]; then
      read -rp "GitHub repository [$detected]: " GITHUB_REPO
      GITHUB_REPO="${GITHUB_REPO:-$detected}"
    else
      read -rp "GitHub repository (owner/repo): " GITHUB_REPO
    fi
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
  [[ -z "$GITHUB_REPO" ]]          && fail "GITHUB_REPO is required"
  [[ -z "$AZURE_SUBSCRIPTION_ID" ]] && fail "AZURE_SUBSCRIPTION_ID is required"
  [[ -z "$AZURE_DEVOPS_PAT" ]]     && fail "AZURE_DEVOPS_PAT is required"

  # Verify Azure CLI auth
  az account show --query '{sub:name, id:id}' -o json >/dev/null 2>&1 || fail "Azure CLI not authenticated. Run: az login"

  # Verify ADO connectivity
  ado_api GET "https://dev.azure.com/$ADO_ORG/_apis/projects/$ADO_PROJECT?api-version=7.1" >/dev/null || fail "Cannot reach ADO project. Check org/project/PAT."

  log "Preflight checks passed."
  log "  ADO Org:         $ADO_ORG"
  log "  ADO Project:     $ADO_PROJECT"
  log "  GitHub Repo:     $GITHUB_REPO"
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

  for role in "Contributor" "Storage Blob Data Contributor"; do
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

  # Find GitHub service connection
  local gh_sc_id
  gh_sc_id=$(ado_api GET "https://dev.azure.com/$ADO_ORG/$ADO_PROJECT/_apis/serviceendpoint/endpoints?api-version=7.1" | \
    jq -r '.value[] | select(.type == "GitHub") | .id' | head -1)

  [[ -z "$gh_sc_id" || "$gh_sc_id" == "null" ]] && fail "No GitHub service connection found in ADO project. Create one first: Project Settings → Service connections → New → GitHub"

  # Check if pipeline already exists
  local existing_pipeline
  existing_pipeline=$(ado_api GET "https://dev.azure.com/$ADO_ORG/$ADO_PROJECT/_apis/build/definitions?api-version=7.1&name=$PIPELINE_NAME" | \
    jq -r '.value[0].id // empty')

  if [[ -n "$existing_pipeline" ]]; then
    warn "Pipeline '$PIPELINE_NAME' already exists (id: $existing_pipeline). Reusing."
    PIPELINE_ID="$existing_pipeline"
  else
    local payload
    payload=$(jq -n \
      --arg name "$PIPELINE_NAME" \
      --arg yaml "$PIPELINE_YAML_PATH" \
      --arg repo "$GITHUB_REPO" \
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

    local result
    result=$(ado_api POST "https://dev.azure.com/$ADO_ORG/$ADO_PROJECT/_apis/build/definitions?api-version=7.1" "$payload")
    PIPELINE_ID=$(echo "$result" | jq -r '.id')

    [[ -z "$PIPELINE_ID" || "$PIPELINE_ID" == "null" ]] && fail "Failed to create pipeline"
  fi

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

  # Set SSH key variable if provided
  if [[ -n "$SSH_PUBLIC_KEY" ]]; then
    updated=$(echo "$updated" | jq --arg key "$SSH_PUBLIC_KEY" '.variables.ADMIN_SSH_PUBLIC_KEY = {"value": $key, "isSecret": true, "allowOverride": true}')
    log "  Pipeline secret ADMIN_SSH_PUBLIC_KEY set."
  else
    warn "  SSH_PUBLIC_KEY not provided. Set ADMIN_SSH_PUBLIC_KEY manually in pipeline variables."
  fi

  ado_api PUT "https://dev.azure.com/$ADO_ORG/$ADO_PROJECT/_apis/build/definitions/$PIPELINE_ID?api-version=7.1" "$updated" >/dev/null

  log "  Pool: Azure Pipelines (queue $queue_id)"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
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
  configure_pipeline

  echo
  log "============================================="
  log "  Setup complete!"
  log "============================================="
  log ""
  log "  Pipeline:    https://dev.azure.com/$ADO_ORG/$ADO_PROJECT/_build?definitionId=$PIPELINE_ID"
  log "  Service Conn: $SERVICE_CONNECTION_NAME (Workload Identity Federation)"
  log "  App Reg:      $APP_ID"
  log ""
  if [[ -z "$SSH_PUBLIC_KEY" ]]; then
    warn "  ACTION REQUIRED: Set ADMIN_SSH_PUBLIC_KEY in pipeline variables"
    warn "  Go to: Pipelines → $PIPELINE_NAME → Edit → Variables → New variable"
    warn "  Name: ADMIN_SSH_PUBLIC_KEY, Value: <ssh-public-key>, Keep secret: ✓"
  fi
  log ""
  log "  To trigger: push to main (infra/terraform/hub/**) or run manually in ADO"
}

main "$@"
