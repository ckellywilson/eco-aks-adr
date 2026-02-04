---
name: terraform/generate-from-json
description: Generate Terraform infrastructure code from flexible JSON schema. Reads JSON configuration with multiple hubs and spokes, creates segregated folder structure with Azure Verified Modules (AVM) for each resource group. Use when engineer provides completed JSON configuration for infrastructure generation.
license: MIT
---

# Generate Terraform from Flexible JSON Skill

## Purpose

This skill automates the generation of Azure infrastructure-as-code (Terraform) from a flexible JSON schema. It supports multi-hub, multi-spoke topologies with different subscription models and resource group segregation.

## When to Use This Skill

Invoke this skill when:
- Engineer provides completed flexible JSON configuration
- User requests: "Generate Terraform from my JSON"
- User requests: "Create infrastructure code from this configuration"
- User needs to generate hub and spoke landing zones

## Task

Generate production-ready Terraform code in segregated folders (`hub-{name}/`, `spoke-{name}/`) based on flexible JSON schema containing metadata, globalConstraints, topology (hubs[], spokes[]), and aksDesign configuration.

## Prerequisites

1. Engineer has provided completed flexible JSON configuration file
2. JSON follows the flexible schema documented in `.github/docs/customer-config-schema.md`
3. Working directory is the repository root

## Instructions

### Step 1: Validate JSON Configuration

**Read the JSON configuration file** provided by the engineer.

**Validate required sections exist:**
```javascript
Required sections:
- metadata (customerName, environment, workshopName, workshopDate, source, notes)
- globalConstraints (region, allowedRegions, subscriptions, namingConventions, requiredTags, complianceStandards)
- topology (pattern, landingZoneModel, hubs[], spokes[])
- aksDesign (clusters[])
```

**Check for critical fields:**
- `topology.hubs[]` must not be empty
- `topology.spokes[]` must not be empty
- Each hub must have: name, subscriptionId, resourceGroup, region, networking
- Each spoke must have: name, type, subscriptionId, resourceGroup, region, hubName
- If spoke has no `resources[]` array, prompt user: 
  ```
  Spoke '{spokeName}' of type '{type}' has no resources specified.
  Should I use default resources for {type} spoke type, or would you like to specify resources?
  
  Default {type} resources:
  - aks: AKS cluster with system and user node pools
  - data: Storage accounts, SQL Database
  - integration: Service Bus, Event Hubs
  - sharedServices: Container Registry, Key Vault
  - other: Base networking only
  ```

### Step 2: Load Code Pattern Templates

**Read code templates from:**
- `.github/prompts/terraform/infrastructure.prompt.md` - Hub and spoke Terraform patterns

This file contains:
- AVM module blocks for hub resources (VNet, Firewall, Bastion, DNS zones, Application Gateway)
- AVM module blocks for spoke types:
  - **aks**: AKS cluster configuration with network plugin, node pools, monitoring
  - **data**: Storage accounts, SQL databases, private endpoints
  - **integration**: Service Bus namespaces, Event Hubs, Logic Apps
  - **sharedServices**: Container Registry, Key Vault, shared Log Analytics
  - **other**: Base VNet, subnets, NSGs, peering
- Provider configuration patterns
- Output file patterns (`{hub-name}-outputs.json`)

### Step 3: Apply Mapping Instructions

**Read mapping logic from:**
- `.github/instructions/terraform-flexible-json-mapping.instructions.md` - JSON-to-Terraform mapping rules
- `.github/instructions/azure-verified-modules-terraform.instructions.md` - AVM compliance rules
- `.github/instructions/generate-modern-terraform-code-for-azure.instructions.md` - Terraform best practices

### Step 4: Determine Provider Aliases

**Analyze subscriptions across all hubs and spokes:**

1. Extract unique `subscriptionId` values from:
   - `topology.hubs[].subscriptionId`
   - `topology.spokes[].subscriptionId`

2. For each unique subscription, create provider alias:
   ```hcl
   provider "azurerm" {
     alias           = "hub-eastus"   # Use hub or spoke name
     subscription_id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
     features {}
   }
   ```

3. Map each hub/spoke to its provider alias for resource generation

### Step 5: Generate Hub Infrastructure

**For each hub in `topology.hubs[]`:**

1. **Create hub directory**: `/infra/terraform/hub-{hub.name}/`

2. **Generate hub files** using patterns from infrastructure.prompt.md:
   - `main.tf` - Hub resources using AVM modules:
     - Resource group
     - VNet with subnets (firewall, bastion, gateway, management, appgw if needed)
     - Azure Firewall (if `hub.firewallType != "none"`)
     - Bastion (if needed for hub architecture)
     - Log Analytics workspace
     - Private DNS zones (from `hub.dnsModel` and `hub.networking.privateDnsZones[]`)
     - Application Gateway (if Tier 1 ingress configured)
   
   - `variables.tf` - Input variables from JSON:
     - environment, location, naming conventions
     - Network configuration (address spaces, subnet prefixes)
     - Conditional resource flags (deploy_firewall, deploy_bastion, deploy_app_gateway)
     - Tags from globalConstraints.requiredTags
   
   - `outputs.tf` - Exports for spoke consumption:
     - hub_vnet_id, hub_vnet_name
     - firewall_private_ip (if deployed)
     - log_analytics_workspace_id
     - private_dns_zone_ids (map of zone names to IDs)
     - bastion_id, app_gateway_id
     - management_subnet_id
   
   - `providers.tf` - Provider with alias:
     ```hcl
     provider "azurerm" {
       alias           = "hub-{hub.name}"
       subscription_id = "{hub.subscriptionId}"
       features {
         resource_group { prevent_deletion_if_contains_resources = true }
         key_vault { purge_soft_delete_on_destroy = false }
       }
     }
     ```
   
   - `terraform.tf` - Terraform configuration:
     ```hcl
     terraform {
       required_version = ">= 1.9"
       required_providers {
         azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
       }
       backend "azurerm" { use_oidc = true }
     }
     ```
   
   - `locals.tf` - Computed values:
     - location_code mapping
     - common_tags merging globalConstraints.requiredTags
     - Conditional logic for resource deployment
   
   - `backend-{env}.tfbackend` - Backend configuration per environment
   
   - `{env}.tfvars` - Environment-specific values
   
   - `README.md` - Hub documentation with deployment instructions

3. **Generate output mechanism**: Create post-apply script that writes outputs to JSON:
   ```bash
   # outputs-to-json.sh
   terraform output -json > {hub.name}-outputs.json
   ```

4. **Apply AVM standards**:
   - All modules use `Azure/avm-{type}-{service}/azurerm` format
   - Pin versions with `~>` syntax
   - Set `enable_telemetry = true` on all AVM modules
   - Use proper naming conventions

### Step 6: Generate Spoke Infrastructure

**For each spoke in `topology.spokes[]`:**

1. **Create spoke directory**: `/infra/terraform/spoke-{spoke.name}/`

2. **Determine spoke resources**:
   - If `spoke.resources[]` exists and not empty: Use specified resources
   - If `spoke.resources[]` is empty or missing: Apply defaults based on `spoke.type`:
     
     **Type: aks**
     - AKS cluster with configuration from `aksDesign.clusters[]` matching `spokeName`
     - System node pool (required)
     - User node pools (from cluster config)
     - Monitoring integration with hub Log Analytics
     - Network configuration (CNI mode, pod CIDR, service CIDR)
     - Private cluster configuration
     - Workload identity setup
     
     **Type: data**
     - Storage accounts with private endpoints
     - Azure SQL Database with private endpoint
     - Private DNS zone links for storage and SQL
     - Data encryption settings
     
     **Type: integration**
     - Service Bus namespace with queues/topics
     - Event Hubs namespace
     - Logic Apps (if specified)
     - Private endpoints for all services
     
     **Type: sharedServices**
     - Azure Container Registry with private endpoint
     - Key Vault with private endpoint
     - Shared Log Analytics workspace (optional)
     - Private DNS zone links
     
     **Type: other**
     - VNet with subnets
     - NSGs
     - Route table
     - VNet peering to hub
     - Basic networking only

3. **Generate spoke files** using patterns from infrastructure.prompt.md:
   
   - `main.tf` - Spoke resources:
     - Resource group
     - VNet with subnets (if spoke manages networking)
     - NSGs and security rules
     - Route table with UDR to firewall (if applicable)
     - VNet peering to hub
     - Spoke-specific resources (from spoke.resources[] or defaults)
   
   - `variables.tf` - Input variables:
     - Hub dependencies (read from data source or remote state)
     - Networking configuration
     - Spoke-specific resource configurations
     - Environment and naming variables
   
   - `outputs.tf` - Spoke outputs:
     - spoke_vnet_id, spoke_vnet_name
     - spoke_resource_group_id
     - Spoke-specific resource outputs (cluster ID, storage IDs, etc.)
   
   - `data-sources.tf` - Hub outputs consumption:
     ```hcl
     locals {
       hub_outputs = jsondecode(file("../hub-{spoke.hubName}/{spoke.hubName}-outputs.json"))
     }
     
     # Use hub outputs
     # local.hub_outputs.firewall_private_ip
     # local.hub_outputs.log_analytics_workspace_id
     # local.hub_outputs.private_dns_zone_ids["privatelink.azurecr.io"]
     ```
   
   - `providers.tf` - Provider with alias:
     ```hcl
     provider "azurerm" {
       alias           = "spoke-{spoke.name}"
       subscription_id = "{spoke.subscriptionId}"
       features {}
     }
     ```
   
   - `terraform.tf` - Same as hub
   
   - `locals.tf` - Computed values for spoke
   
   - `backend-{env}.tfbackend` - Spoke backend config
   
   - `{env}.tfvars` - Spoke environment values
   
   - `README.md` - Spoke documentation with deployment order (deploy hub first)

4. **For AKS spokes, integrate aksDesign configuration**:
   - Match spoke to cluster in `aksDesign.clusters[]` by `spokeName`
   - Apply cluster architecture (clusterSku, kubernetesVersion, availabilityZones)
   - Configure node pools from `nodePools[]` array
   - Set networking (networkPlugin, networkPolicy, serviceCidr, podCidr, outboundType)
   - Configure identity (controlPlaneIdentityType, kubeletIdentityType)
   - Apply security settings (privateClusterEnabled, authorizedIpRanges, podSecurityModel, secretsManagement)
   - Set observability (logs, metrics, logAnalyticsWorkspaceId, additionalTools)
   - Configure delivery model (gitOpsEnabled, gitOpsTool, ciCdModel)
   - Configure ingress (ingressController, apiGateway, internalOnly)

5. **Handle cross-subscription VNet peering**:
   - If `spoke.subscriptionId != hub.subscriptionId`:
     - Create peering from spoke to hub using spoke provider
     - Create peering from hub to spoke using hub provider
     - Document RBAC requirements (Network Contributor role needed)

### Step 7: Generate Resource-Specific Configurations

**For each resource in spoke.resources[]:**

Generate Terraform resources based on resource.type using AVM modules:

```javascript
Resource type mapping:
- storageAccount -> Azure/avm-res-storage-storageaccount/azurerm
- sqlDatabase -> Azure/avm-res-sql-server/azurerm
- serviceBus -> Azure/avm-res-servicebus-namespace/azurerm
- eventHub -> Azure/avm-res-eventhub-namespace/azurerm
- containerRegistry -> Azure/avm-res-containerregistry-registry/azurerm
- keyVault -> Azure/avm-res-keyvault-vault/azurerm
- aksCluster -> Azure/avm-res-containerservice-managedcluster/azurerm
```

**Use resource properties from JSON:**
- resource.name -> resource name
- resource.sku -> SKU/pricing tier
- resource.properties -> additional configuration

### Step 8: Generate Supporting Files

**For each hub and spoke directory, create:**

1. **Deployment script** (`deploy.sh`):
   ```bash
   #!/bin/bash
   set -e
   
   ENV=${1:-dev}
   
   echo "Deploying {folder-name} to $ENV"
   
   terraform init -backend-config=backend-$ENV.tfbackend
   terraform plan -var-file=$ENV.tfvars -out=tfplan
   terraform apply tfplan
   
   # For hubs: Generate outputs JSON
   terraform output -json > {hub-name}-outputs.json
   ```

2. **.terraform.lock.hcl** placeholder (will be generated on first init and should be committed)

3. **.gitignore**:
   ```
   .terraform/
   *.tfstate
   *.tfstate.backup
   tfplan
   ```

### Step 9: Validate Generated Code

**Run Tier 1 validation on generated Terraform:**

```bash
# Format all Terraform code
terraform fmt -recursive

# Validate syntax (without init, just check structure)
for dir in infra/terraform/hub-* infra/terraform/spoke-*; do
  echo "Validating $dir"
  cd $dir
  terraform init -backend=false
  terraform validate
  cd -
done
```

**Check AVM compliance:**
- All modules use `Azure/avm-*` source
- All modules have pinned versions (~> syntax)
- All modules have `enable_telemetry = true`
- No hardcoded values (use variables)
- All variables have descriptions
- Outputs are properly exported

### Step 10: Generate Summary Documentation

**Create root-level README** (`/infra/terraform/README.md`):

```markdown
# Azure Infrastructure - Terraform

Generated from flexible JSON schema on {date}.

## Architecture Overview

**Topology Pattern**: {topology.pattern}
**Landing Zone Model**: {topology.landingZoneModel}

### Hubs ({count})
{list hubs with names, regions, subscriptions}

### Spokes ({count})
{list spokes with names, types, regions, linked hubs}

## Deployment Order

1. **Deploy Hubs First** (can be deployed in parallel):
   {list hub deployment commands}

2. **Deploy Spokes** (after hubs are complete):
   {list spoke deployment commands with dependencies}

## Prerequisites

- Terraform >= 1.9
- Azure CLI >= 2.50
- Appropriate Azure subscriptions and permissions
- Service principal or managed identity with Contributor role

### Multi-Subscription Setup

{if multiple subscriptions detected}
This deployment spans multiple subscriptions:
{list subscriptions and their roles}

Required RBAC:
- Contributor on each subscription
- Network Contributor for cross-subscription VNet peering

## Configuration Files

- **JSON Source**: {path to JSON file}
- **Schema Reference**: `.github/docs/customer-config-schema.md`
- **Instructions**: `.github/instructions/terraform-flexible-json-mapping.instructions.md`

## Validation

Before deployment, validate the code:
```bash
# Format and validate
terraform fmt -recursive
./validate-all.sh

# Run security scan
tfsec . --minimum-severity MEDIUM
```

## Deployment

### Deploy a Hub

```bash
cd infra/terraform/hub-{name}
./deploy.sh dev   # or staging, prod
```

### Deploy a Spoke

```bash
cd infra/terraform/spoke-{name}
./deploy.sh dev   # or staging, prod
```

## Generated Structure

```
infra/terraform/
├── README.md (this file)
├── hub-{name}/           # Hub landing zone
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── providers.tf
│   ├── terraform.tf
│   ├── locals.tf
│   ├── backend-dev.tfbackend
│   ├── backend-prod.tfbackend
│   ├── dev.tfvars
│   ├── prod.tfvars
│   ├── deploy.sh
│   ├── {hub-name}-outputs.json  # Generated after apply
│   └── README.md
├── spoke-{name}/         # Spoke (aks, data, integration, etc.)
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── data-sources.tf  # Reads hub outputs
│   ├── providers.tf
│   ├── terraform.tf
│   ├── locals.tf
│   ├── backend-dev.tfbackend
│   ├── backend-prod.tfbackend
│   ├── dev.tfvars
│   ├── prod.tfvars
│   ├── deploy.sh
│   └── README.md
└── validate-all.sh       # Validation script for all folders
```

## Modification

To modify the infrastructure:
1. Update the source JSON configuration
2. Re-run the generate skill: "Generate Terraform from my JSON"
3. Review changes with `git diff`
4. Validate with `terraform plan`
5. Apply updates with `terraform apply`

## Support

- **AVM Modules**: https://azure.github.io/Azure-Verified-Modules/
- **Terraform Azure Provider**: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs
- **Schema Documentation**: `.github/docs/customer-config-schema.md`
```

### Step 11: Create Validation Helper Script

**Generate `/infra/terraform/validate-all.sh`:**

```bash
#!/bin/bash
set -e

echo "================================"
echo "Validating All Terraform Code"
echo "================================"
echo ""

# Format check
echo "Running terraform fmt..."
terraform fmt -recursive -check
echo "✓ Formatting passed"
echo ""

# Validate each directory
for dir in hub-* spoke-*; do
  if [ -d "$dir" ]; then
    echo "Validating $dir..."
    cd "$dir"
    
    # Init without backend
    terraform init -backend=false > /dev/null 2>&1
    
    # Validate
    if terraform validate; then
      echo "✓ $dir validated"
    else
      echo "✗ $dir validation failed"
      exit 1
    fi
    
    cd ..
    echo ""
  fi
done

echo "================================"
echo "✓ All Terraform code validated"
echo "================================"
```

Make executable:
```bash
chmod +x /infra/terraform/validate-all.sh
```

### Step 12: Provide User Guidance

**Output completion message:**

```
✅ Terraform Infrastructure Generated Successfully!

📁 Generated Structure:
- {count} hubs in /infra/terraform/hub-*/
- {count} spokes in /infra/terraform/spoke-*/

📋 Next Steps:

1. Review generated code:
   cd /infra/terraform
   ls -la

2. Validate code:
   ./validate-all.sh

3. Review hub configurations:
   cat hub-{name}/README.md

4. Review spoke configurations:
   cat spoke-{name}/README.md

5. Deploy (in order):
   # Deploy hubs first
   cd hub-{name} && ./deploy.sh dev
   
   # Deploy spokes after hubs
   cd spoke-{name} && ./deploy.sh dev

6. Commit changes:
   git add infra/terraform/
   git commit -m "feat(terraform): generate infrastructure from flexible JSON schema
   
   Fixes #64"

⚠️  Remember:
- Deploy hubs before spokes
- Hub outputs are written to {hub-name}-outputs.json after apply
- Spokes read hub outputs from ../hub-{name}/{hub-name}-outputs.json
- For multi-subscription deployments, ensure Network Contributor role is assigned

📚 Documentation:
- Architecture: /infra/terraform/README.md
- JSON Schema: .github/docs/customer-config-schema.md
- Mapping Rules: .github/instructions/terraform-flexible-json-mapping.instructions.md
```

## Success Criteria

Terraform generation is complete when:
- [ ] All hub directories created in `/infra/terraform/hub-*/`
- [ ] All spoke directories created in `/infra/terraform/spoke-*/`
- [ ] Each hub has complete Terraform files (main, variables, outputs, providers, terraform, locals, backend configs, tfvars, README)
- [ ] Each spoke has complete Terraform files including data-sources.tf for hub outputs
- [ ] Provider aliases generated for all unique subscriptions
- [ ] AVM modules used for all resources with pinned versions
- [ ] `enable_telemetry = true` on all AVM modules
- [ ] Hub output mechanism configured ({hub-name}-outputs.json)
- [ ] Spoke hub-consumption mechanism configured (jsondecode file read)
- [ ] Default resources applied for spokes without explicit resource specifications
- [ ] Cross-subscription VNet peering configured correctly (if applicable)
- [ ] AKS cluster configuration integrated from aksDesign section
- [ ] Root README.md generated with deployment instructions
- [ ] validate-all.sh script created and executable
- [ ] `terraform fmt -recursive` passes
- [ ] `terraform validate` passes for all directories (with -backend=false)
- [ ] User provided clear next steps

## Common Issues and Solutions

### Issue: JSON validation fails
**Solution**: Check that JSON has all required sections (metadata, globalConstraints, topology, aksDesign). Verify hubs[] and spokes[] are not empty.

### Issue: Spoke references hub that doesn't exist
**Solution**: Verify `spoke.hubName` matches a `hub.name` in topology.hubs[]. Hub names are case-sensitive.

### Issue: Resource type not recognized
**Solution**: Check that spoke.resources[].type is one of the supported types. Reference `.github/instructions/terraform-flexible-json-mapping.instructions.md` for valid types.

### Issue: AKS cluster configuration not found
**Solution**: Ensure `aksDesign.clusters[]` has an entry where `spokeName` matches the AKS spoke's name.

### Issue: terraform validate fails with module not found
**Solution**: This is expected before `terraform init`. Validation with `-backend=false` only checks syntax, not module availability.

### Issue: Multi-subscription peering fails
**Solution**: Verify Network Contributor role is assigned on both subscriptions for the service principal deploying the infrastructure.

## Integration with Workflow

This skill integrates with repository workflow from `.github/copilot-instructions.md`:

**Usage Pattern:**
```
Engineer creates JSON → Provides to Copilot → Copilot generates Terraform → Engineer validates → Engineer deploys
```

**After generation:**
1. Run validation: "Validate my Terraform code" (uses validate-terraform skill)
2. Commit changes with conventional commits
3. Create PR
4. Request Copilot review
5. Deploy in proper order (hubs → spokes)

## Resources Referenced

- `.github/prompts/terraform/infrastructure.prompt.md` - Terraform code patterns
- `.github/instructions/terraform-flexible-json-mapping.instructions.md` - JSON mapping rules
- `.github/instructions/azure-verified-modules-terraform.instructions.md` - AVM standards
- `.github/instructions/generate-modern-terraform-code-for-azure.instructions.md` - Terraform best practices
- `.github/docs/customer-config-schema.md` - Flexible JSON schema reference

## Notes

- This skill generates Terraform only (Bicep support will be added in future via separate skill)
- Hub outputs are file-based ({hub-name}-outputs.json) for simplicity
- Spoke reads hub outputs via `jsondecode(file(...))` pattern
- Provider aliases use resource names with subscription_id for clarity
- Folder structure is future-proof for Bicep generation (terraform/ subfolder)
- Default resources are applied per spoke type when resources[] not specified
- AVM modules are mandatory for Azure resource creation
- All generated code follows Azure Verified Modules standards
