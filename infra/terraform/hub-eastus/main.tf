resource "azurerm_resource_group" "hub" {
  name     = var.resource_group_name
  location = var.location

  tags = local.common_tags
}

# Hub VNet with subnets
module "hub_vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "~> 0.4"

  name      = "vnet-hub-${var.environment}-${local.location_code}"
  parent_id = azurerm_resource_group.hub.id
  location  = var.location

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
}

# Azure Firewall
module "firewall" {
  count   = var.deploy_firewall ? 1 : 0
  source  = "Azure/avm-res-network-azurefirewall/azurerm"
  version = "~> 0.3"

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

# Azure Bastion
module "bastion" {
  count   = var.deploy_bastion ? 1 : 0
  source  = "Azure/avm-res-network-bastionhost/azurerm"
  version = "~> 0.3"

  name      = "bas-hub-${var.environment}-${local.location_code}"
  location  = var.location
  parent_id = azurerm_resource_group.hub.id
  sku       = var.bastion_sku

  ip_configuration = {
    name      = "ipconfig1"
    subnet_id = module.hub_vnet.subnets["AzureBastionSubnet"].resource_id
  }

  enable_telemetry = true
  tags             = local.common_tags
}

# Log Analytics Workspace
module "log_analytics" {
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "~> 0.4"

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
  version = "~> 0.2"

  domain_name = each.value
  parent_id   = azurerm_resource_group.hub.id

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

    rule {
      name = "aks-api-server"
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses  = ["*"]
      destination_fqdns = ["*.hcp.${var.location}.azmk8s.io"]
    }

    rule {
      name = "microsoft-container-registry"
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses  = ["*"]
      destination_fqdns = ["mcr.microsoft.com", "*.cdn.mscr.io", "*.data.mcr.microsoft.com"]
    }

    rule {
      name = "azure-management"
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses = ["*"]
      destination_fqdns = [
        "management.azure.com",
        "login.microsoftonline.com",
        "packages.microsoft.com",
        "acs-mirror.azureedge.net"
      ]
    }

    rule {
      name = "azure-monitor"
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses = ["*"]
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
      source_addresses  = ["*"]
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
      source_addresses      = ["*"]
      destination_addresses = ["*"]
      destination_ports     = ["53"]
    }

    rule {
      name                  = "ntp"
      protocols             = ["UDP"]
      source_addresses      = ["*"]
      destination_addresses = ["*"]
      destination_ports     = ["123"]
    }

    rule {
      name                  = "https"
      protocols             = ["TCP"]
      source_addresses      = ["*"]
      destination_addresses = ["*"]
      destination_ports     = ["443"]
    }
  }
}

# ===========================
# Hub-to-Spoke VNet Peering
# ===========================

data "azurerm_virtual_network" "spoke" {
  for_each = var.spoke_vnets

  name                = each.value.name
  resource_group_name = each.value.resource_group_name
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  for_each = var.spoke_vnets

  name                         = "peer-hub-to-${each.key}"
  resource_group_name          = azurerm_resource_group.hub.name
  virtual_network_name         = module.hub_vnet.name
  remote_virtual_network_id    = data.azurerm_virtual_network.spoke[each.key].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  for_each = var.spoke_vnets

  name                         = "peer-${each.key}-to-hub"
  resource_group_name          = each.value.resource_group_name
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
  name                = "vm-jumpbox-hub-${var.location_code}-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.hub.name
  size                = "Standard_D2s_v3"
  admin_username      = var.admin_username

  network_interface_ids = [
    azurerm_network_interface.hub_jumpbox.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
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
    
    # Install Azure CLI
    curl -sL https://aka.ms/InstallAzureCLIDeb | bash
    
    # Verify Azure CLI installation
    if ! command -v az >/dev/null 2>&1; then
      log "ERROR: Azure CLI (az) not found after installation."
      exit 1
    fi
    
    # Install kubectl
    KUBECTL_VERSION="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
    chmod +x kubectl
    mv kubectl /usr/local/bin/
    
    # Verify kubectl installation
    if ! command -v kubectl >/dev/null 2>&1; then
      log "ERROR: kubectl not found after installation."
      exit 1
    fi
    
    # Install Helm
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    
    # Verify Helm installation
    if ! command -v helm >/dev/null 2>&1; then
      log "ERROR: Helm not found after installation."
      exit 1
    fi
    
    # Install k9s
    curl -sS https://webinstall.dev/k9s | bash
    
    # Verify k9s installation
    if ! command -v k9s >/dev/null 2>&1; then
      log "ERROR: k9s not found after installation."
      exit 1
    fi
    
    # Install jq and other tools
    apt-get install -y jq vim curl wget git
    
    # Verify jq installation (as representative of apt-installed tools)
    if ! command -v jq >/dev/null 2>&1; then
      log "ERROR: jq not found after installation."
      exit 1
    fi
    
    log "INFO: Jump box provisioning completed successfully."
  EOT
  )

  tags = merge(var.tags, {
    Purpose = "Jump Box - Hub Management"
  })
}

