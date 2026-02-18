resource "azurerm_resource_group" "hub" {
  name     = var.resource_group_name
  location = var.location

  tags = local.common_tags
}

# Hub VNet with subnets
module "hub_vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.9.0"

  resource_group_name = azurerm_resource_group.hub.name
  name                = "vnet-hub-${var.environment}-${local.location_code}"
  location            = var.location

  address_space = var.hub_vnet_address_space

  subnets = local.subnet_config

  enable_telemetry = true
  tags             = local.common_tags
}

# Azure Firewall
# Public IP for Firewall
resource "azurerm_public_ip" "firewall" {
  count               = var.deploy_firewall ? 1 : 0
  name                = "pip-afw-hub-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = local.common_tags

  lifecycle {
    ignore_changes = [ip_tags]
  }
}

# Azure Firewall
module "firewall" {
  count   = var.deploy_firewall ? 1 : 0
  source  = "Azure/avm-res-network-azurefirewall/azurerm"
  version = "0.4.0"

  name                = "afw-hub-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location
  firewall_sku_tier   = var.firewall_sku_tier
  firewall_sku_name   = "AZFW_VNet"
  firewall_zones      = var.firewall_availability_zones
  firewall_policy_id  = azurerm_firewall_policy.hub[0].id

  ip_configurations = {
    ipconfig1 = {
      name                 = "ipconfig1"
      subnet_id            = module.hub_vnet.subnets["AzureFirewallSubnet"].resource_id
      public_ip_address_id = azurerm_public_ip.firewall[0].id
    }
  }

  enable_telemetry = true
  tags             = local.common_tags

  depends_on = [azurerm_firewall_policy.hub]
}

# Firewall Policy
resource "azurerm_firewall_policy" "hub" {
  count               = var.deploy_firewall ? 1 : 0
  name                = "afwpol-hub-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location

  tags = local.common_tags
}

# Public IP for Bastion
resource "azurerm_public_ip" "bastion" {
  count               = var.deploy_bastion ? 1 : 0
  name                = "pip-bas-hub-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = local.common_tags

  lifecycle {
    ignore_changes = [ip_tags]
  }
}

# Azure Bastion
module "bastion" {
  count   = var.deploy_bastion ? 1 : 0
  source  = "Azure/avm-res-network-bastionhost/azurerm"
  version = "0.4.0"

  name                = "bas-hub-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location
  sku                 = var.bastion_sku

  ip_configuration = {
    name                 = "ipconfig1"
    subnet_id            = module.hub_vnet.subnets["AzureBastionSubnet"].resource_id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }

  enable_telemetry = true
  tags             = local.common_tags
}

# Log Analytics Workspace
module "log_analytics" {
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "0.5.0"

  name                = "law-hub-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location

  log_analytics_workspace_retention_in_days = var.log_retention_days
  log_analytics_workspace_sku               = var.log_analytics_sku

  enable_telemetry = true
  tags             = local.common_tags
}

# Private DNS Zones
module "private_dns_zones" {
  for_each = toset(var.private_dns_zones)

  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.3.0"

  resource_group_name = azurerm_resource_group.hub.name
  domain_name         = each.value

  virtual_network_links = {
    hub_vnet = {
      vnetlinkname = "link-${each.value}-hub"
      vnetid       = module.hub_vnet.resource_id
    }
  }

  enable_telemetry = true
  tags             = local.common_tags
}

# Azure Private DNS Resolver
resource "azurerm_private_dns_resolver" "hub" {
  count               = var.deploy_dns_resolver ? 1 : 0
  name                = "dnspr-hub-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location
  virtual_network_id  = module.hub_vnet.resource_id

  tags = local.common_tags
}

# DNS Resolver Inbound Endpoint
resource "azurerm_private_dns_resolver_inbound_endpoint" "hub" {
  count                   = var.deploy_dns_resolver ? 1 : 0
  name                    = "dnspr-in-hub-${var.environment}-${local.location_code}"
  private_dns_resolver_id = azurerm_private_dns_resolver.hub[0].id
  location                = var.location

  ip_configurations {
    private_ip_allocation_method = "Dynamic"
    subnet_id                    = module.hub_vnet.subnets["dns_resolver_inbound"].resource_id
  }

  tags = local.common_tags
}

# DNS Resolver Outbound Endpoint
resource "azurerm_private_dns_resolver_outbound_endpoint" "hub" {
  count                   = var.deploy_dns_resolver ? 1 : 0
  name                    = "dnspr-out-hub-${var.environment}-${local.location_code}"
  private_dns_resolver_id = azurerm_private_dns_resolver.hub[0].id
  location                = var.location
  subnet_id               = module.hub_vnet.subnets["dns_resolver_outbound"].resource_id

  tags = local.common_tags
}

# DNS Forwarding Ruleset
resource "azurerm_private_dns_resolver_dns_forwarding_ruleset" "hub" {
  count                                      = var.deploy_dns_resolver ? 1 : 0
  name                                       = "dnspr-fwd-hub-${var.environment}-${local.location_code}"
  resource_group_name                        = azurerm_resource_group.hub.name
  location                                   = var.location
  private_dns_resolver_outbound_endpoint_ids = [azurerm_private_dns_resolver_outbound_endpoint.hub[0].id]

  tags = local.common_tags
}

# DNS Forwarding Rule for corp.ecolab.com
resource "azurerm_private_dns_resolver_forwarding_rule" "corp_ecolab" {
  count                     = var.deploy_dns_resolver && length(var.onprem_dns_servers) > 0 ? 1 : 0
  name                      = "corp-ecolab-com"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub[0].id
  domain_name               = "corp.ecolab.com."
  enabled                   = true

  dynamic "target_dns_servers" {
    for_each = var.onprem_dns_servers
    content {
      ip_address = target_dns_servers.value
      port       = 53
    }
  }
}

# DNS Forwarding Rule for local
resource "azurerm_private_dns_resolver_forwarding_rule" "local" {
  count                     = var.deploy_dns_resolver && length(var.onprem_dns_servers) > 0 ? 1 : 0
  name                      = "local"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub[0].id
  domain_name               = "local."
  enabled                   = true

  dynamic "target_dns_servers" {
    for_each = var.onprem_dns_servers
    content {
      ip_address = target_dns_servers.value
      port       = 53
    }
  }
}

# DNS Forwarding Rule for AKS Private DNS Zone
# NOTE: This forwarding rule is NOT needed because:
# 1. The AKS private DNS zone (privatelink.eastus2.azmk8s.io) is linked to the hub VNet
# 2. The DNS resolver can directly resolve private DNS zones linked to its VNet
# 3. Azure doesn't allow forwarding to 168.63.129.16 in forwarding rules
# 4. The ruleset VNET link (below) enables the resolver to process queries and resolve
#    private DNS zones without explicit forwarding rules
# Reference: https://learn.microsoft.com/en-us/azure/dns/private-resolver-endpoints-rulesets#rules
#
# Previous incorrect configuration (removed):
# resource "azurerm_private_dns_resolver_forwarding_rule" "aks_private_zone" {
#   domain_name = "privatelink.eastus2.azmk8s.io."
#   target_dns_servers { ip_address = "168.63.129.16" }  # ❌ Not allowed
# }

# Link DNS Forwarding Ruleset to Hub VNet
# Required for centralized DNS architecture: when spoke VNets use the hub's inbound endpoint
# as custom DNS, the ruleset must be linked to the hub VNet to apply forwarding rules to
# incoming queries from those spokes.
# Reference: https://learn.microsoft.com/en-us/azure/dns/private-resolver-endpoints-rulesets#inbound-endpoints-as-custom-dns
resource "azurerm_private_dns_resolver_virtual_network_link" "hub_vnet_link" {
  count                     = var.deploy_dns_resolver ? 1 : 0
  name                      = "link-hub-vnet-to-ruleset-${var.environment}-${local.location_code}"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub[0].id
  virtual_network_id        = module.hub_vnet.resource_id
}

# Firewall Policy Rule Collection Group
resource "azurerm_firewall_policy_rule_collection_group" "aks" {
  count              = var.deploy_firewall ? 1 : 0
  name               = "aks-rules"
  firewall_policy_id = azurerm_firewall_policy.hub[0].id
  priority           = 100

  application_rule_collection {
    name     = "aks-dependencies"
    priority = 110
    action   = "Allow"

    # Use Azure-managed FQDN tag — auto-maintained by Microsoft with current AKS egress FQDNs.
    # Replaces manually enumerated FQDNs (MCR, AKS API, management endpoints, etc.)
    # Reference: https://learn.microsoft.com/en-us/azure/firewall/fqdn-tags
    rule {
      name = "aks-fqdn-tag"
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses      = local.allowed_source_addresses
      destination_fqdn_tags = ["AzureKubernetesService"]
    }
  }

  application_rule_collection {
    name     = "shared-dependencies"
    priority = 200
    action   = "Allow"

    rule {
      name = "azure-monitor"
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses = local.allowed_source_addresses
      destination_fqdns = [
        "*.ods.opinsights.azure.com",
        "*.oms.opinsights.azure.com",
        "*.monitoring.azure.com"
      ]
    }

    rule {
      name = "azure-container-registry"
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses  = local.allowed_source_addresses
      destination_fqdns = ["*.azurecr.io"]
    }
  }

  network_rule_collection {
    name     = "aks-network-requirements"
    priority = 120
    action   = "Allow"

    rule {
      name                  = "dns"
      protocols             = ["UDP", "TCP"]
      source_addresses      = local.allowed_source_addresses
      destination_addresses = ["168.63.129.16"] # Azure DNS
      destination_ports     = ["53"]
    }

    rule {
      name                  = "ntp"
      protocols             = ["UDP"]
      source_addresses      = local.allowed_source_addresses
      destination_addresses = ["*"] # NTP servers worldwide
      destination_ports     = ["123"]
    }

    rule {
      name                  = "https"
      protocols             = ["TCP"]
      source_addresses      = local.allowed_source_addresses
      destination_addresses = ["AzureCloud"] # Azure service tag
      destination_ports     = ["443"]
    }
  }
}

# ===========================
# Hub-Managed Spoke Resources
# ===========================
# When hub_managed = true, the hub creates the spoke RG + VNet.
# Spoke deployments deploy INTO these resources via remote state.
# When hub_managed = false, the spoke RG + VNet must already exist.

resource "azurerm_resource_group" "spoke" {
  for_each = local.hub_managed_spokes

  name     = each.value.resource_group_name
  location = var.location

  tags = local.common_tags
}

module "spoke_vnet" {
  for_each = local.hub_managed_spokes

  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.9.0"

  resource_group_name = azurerm_resource_group.spoke[each.key].name
  name                = each.value.name
  location            = var.location

  address_space = each.value.address_space

  # Custom DNS → hub DNS resolver inbound endpoint
  # This is the key architectural requirement for the DNS resolution chain
  dns_servers = {
    dns_servers = [azurerm_private_dns_resolver_inbound_endpoint.hub[0].ip_configurations[0].private_ip_address]
  }

  enable_telemetry = true
  tags             = local.common_tags

  depends_on = [azurerm_private_dns_resolver_inbound_endpoint.hub]
}

# ===========================
# Hub-to-Spoke VNet Peering
# ===========================

# Data source for delegated spokes (hub_managed = false) — must already exist
data "azurerm_virtual_network" "spoke" {
  for_each = local.delegated_spokes

  name                = each.value.name
  resource_group_name = each.value.resource_group_name
}

# Hub-to-Spoke Peering (both modes)
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  for_each = var.spoke_vnets

  name                 = "peer-hub-to-${each.key}"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = module.hub_vnet.name
  remote_virtual_network_id = (
    each.value.hub_managed
    ? module.spoke_vnet[each.key].resource_id
    : data.azurerm_virtual_network.spoke[each.key].id
  )
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

# Spoke-to-Hub Peering (both modes)
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  for_each = var.spoke_vnets

  name = "peer-${each.key}-to-hub"
  resource_group_name = (
    each.value.hub_managed
    ? azurerm_resource_group.spoke[each.key].name
    : each.value.resource_group_name
  )
  virtual_network_name         = each.value.name
  remote_virtual_network_id    = module.hub_vnet.resource_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

# ===========================
# Jump Box VM - Hub
# ===========================

resource "azurerm_network_interface" "hub_jumpbox" {
  count               = var.deploy_jumpbox ? 1 : 0
  name                = "nic-jumpbox-hub-${var.location_code}-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.hub.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = module.hub_vnet.subnets["management"].resource_id
    private_ip_address_allocation = "Dynamic"
  }

  tags = var.tags
}

resource "azurerm_linux_virtual_machine" "hub_jumpbox" {
  count               = var.deploy_jumpbox ? 1 : 0
  name                = "vm-jumpbox-hub-${var.location_code}-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.hub.name
  size                = "Standard_D2s_v3"
  admin_username      = var.admin_username

  network_interface_ids = [
    azurerm_network_interface.hub_jumpbox[0].id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = data.azurerm_key_vault_secret.ssh_public_key[0].value
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }
  custom_data = base64encode(<<-EOT
    #!/bin/bash
    set -euo pipefail
    
    LOG_FILE="/var/log/jumpbox-setup.log"
    
    # Ensure log directory and file exist
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    # Redirect all output to log file
    exec >>"$LOG_FILE" 2>&1
    
    log() {
      echo "$(date -Iseconds) [$$] $*"
    }
    
    # Trap any error and log before exiting
    trap 'log "ERROR: Jump box provisioning failed at line $LINENO."; exit 1' ERR
    
    log "INFO: Starting jump box provisioning."
    
    export DEBIAN_FRONTEND=noninteractive
    
    # Update system
    apt-get update -y
    apt-get upgrade -y
    
    # Install jq, vim, curl, wget, git from distro packages (verified by package manager)
    apt-get install -y jq vim curl wget git ca-certificates gnupg lsb-release
    
    # Verify apt-installed tools
    if ! command -v jq >/dev/null 2>&1; then
      log "ERROR: jq not found after installation."
      exit 1
    fi
    
    # Install Azure CLI using Microsoft's signed repository
    log "INFO: Installing Azure CLI from Microsoft repository."
    curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null
    AZ_REPO=$(lsb_release -cs)
    echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | tee /etc/apt/sources.list.d/azure-cli.list
    apt-get update -y
    apt-get install -y azure-cli
    
    # Verify Azure CLI installation
    if ! command -v az >/dev/null 2>&1; then
      log "ERROR: Azure CLI (az) not found after installation."
      exit 1
    fi
    
    # Install kubectl with checksum verification
    log "INFO: Installing kubectl with checksum verification."
    KUBECTL_VERSION="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
    curl -LO "https://dl.k8s.io/release/$${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
    curl -LO "https://dl.k8s.io/$${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256"
    
    # Verify kubectl checksum
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check || {
      log "ERROR: kubectl checksum verification failed."
      exit 1
    }
    
    chmod +x kubectl
    mv kubectl /usr/local/bin/
    rm -f kubectl.sha256
    
    # Verify kubectl installation
    if ! command -v kubectl >/dev/null 2>&1; then
      log "ERROR: kubectl not found after installation."
      exit 1
    fi
    
    # Install Helm from official GitHub releases with checksum verification
    log "INFO: Installing Helm from GitHub releases."
    HELM_VERSION="v3.13.3"
    HELM_TARBALL="helm-$${HELM_VERSION}-linux-amd64.tar.gz"
    HELM_CHECKSUM_URL="https://get.helm.sh/$${HELM_TARBALL}.sha256sum"
    
    curl -LO "https://get.helm.sh/$${HELM_TARBALL}"
    curl -LO "$${HELM_CHECKSUM_URL}"
    
    # Verify Helm checksum
    sha256sum --check "$${HELM_TARBALL}.sha256sum" --ignore-missing || {
      log "ERROR: Helm checksum verification failed."
      exit 1
    }
    
    tar -zxvf "$${HELM_TARBALL}"
    mv linux-amd64/helm /usr/local/bin/helm
    rm -rf linux-amd64 "$${HELM_TARBALL}" "$${HELM_TARBALL}.sha256sum"
    
    # Verify Helm installation
    if ! command -v helm >/dev/null 2>&1; then
      log "ERROR: Helm not found after installation."
      exit 1
    fi
    
    # Install k9s from official GitHub releases with checksum verification
    log "INFO: Installing k9s from GitHub releases."
    K9S_VERSION="v0.31.7"
    K9S_TARBALL="k9s_Linux_amd64.tar.gz"
    K9S_URL="https://github.com/derailed/k9s/releases/download/$${K9S_VERSION}/$${K9S_TARBALL}"
    K9S_CHECKSUM_URL="https://github.com/derailed/k9s/releases/download/$${K9S_VERSION}/checksums.sha256"
    
    curl -LO "$${K9S_URL}"
    curl -LO "$${K9S_CHECKSUM_URL}"
    
    # Verify k9s checksum
    grep "$${K9S_TARBALL}" checksums.sha256 | sha256sum --check || {
      log "ERROR: k9s checksum verification failed."
      exit 1
    }
    
    tar -zxvf "$${K9S_TARBALL}" k9s
    mv k9s /usr/local/bin/k9s
    rm -f "$${K9S_TARBALL}" checksums.sha256
    
    # Verify k9s installation
    if ! command -v k9s >/dev/null 2>&1; then
      log "ERROR: k9s not found after installation."
      exit 1
    fi
    
    log "INFO: Jump box provisioning completed successfully."
  EOT
  )

  tags = merge(var.tags, {
    Purpose = "Jump Box - Hub Management"
  })
}

