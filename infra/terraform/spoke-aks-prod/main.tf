resource "azurerm_resource_group" "aks_spoke" {
  name     = var.resource_group_name
  location = var.location

  tags = local.common_tags
}

# User-assigned managed identities
resource "azurerm_user_assigned_identity" "aks_control_plane" {
  name                = "uami-aks-cp-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.aks_spoke.name
  location            = var.location

  tags = local.common_tags
}

resource "azurerm_user_assigned_identity" "aks_kubelet" {
  name                = "uami-aks-kubelet-${var.environment}-${local.location_code}"
  resource_group_name = azurerm_resource_group.aks_spoke.name
  location            = var.location

  tags = local.common_tags
}

# Spoke VNet with subnets
module "spoke_vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "~> 0.4"

  name      = "vnet-aks-${var.environment}-${local.location_code}"
  parent_id = azurerm_resource_group.aks_spoke.id
  location  = var.location

  address_space = var.spoke_vnet_address_space

  # Point to hub DNS Resolver inbound endpoint
  dns_servers = try(
    [local.hub_outputs.dns_resolver_inbound_ip],
    var.custom_dns_servers,
    null
  )

  subnets = local.subnet_config

  enable_telemetry = true
  tags             = local.common_tags
}

# Route table for spoke with UDR to hub firewall
resource "azurerm_route_table" "spoke" {
  name                = "rt-spoke-${var.environment}-${local.location_code}"
  location            = var.location
  resource_group_name = azurerm_resource_group.aks_spoke.name

  tags = local.common_tags
}

# Default route to hub firewall (0.0.0.0/0 -> Firewall Private IP)
resource "azurerm_route" "default_route" {
  name                = "route-default-to-firewall"
  resource_group_name = azurerm_resource_group.aks_spoke.name
  route_table_name    = azurerm_route_table.spoke.name
  address_prefix      = "0.0.0.0/0"
  next_hop_type       = "VirtualAppliance"
  next_hop_in_ip_address = try(
    local.hub_outputs.firewall_private_ip,
    "10.0.1.4" # Default firewall IP if hub not deployed yet
  )
}

# Associate route table with AKS node pools subnet
resource "azurerm_subnet_route_table_association" "aks_nodes" {
  subnet_id      = module.spoke_vnet.subnets["aks_nodes"].resource_id
  route_table_id = azurerm_route_table.spoke.id
}

# Network Security Group for AKS nodes
resource "azurerm_network_security_group" "aks_nodes" {
  name                = "nsg-aks-nodes-${var.environment}-${local.location_code}"
  location            = var.location
  resource_group_name = azurerm_resource_group.aks_spoke.name

  security_rule {
    name                       = "AllowIntraSubnet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.1.0.0/22"
    destination_address_prefix = "10.1.0.0/22"
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = local.common_tags
}

# Associate NSG with AKS node pools subnet
resource "azurerm_subnet_network_security_group_association" "aks_nodes" {
  subnet_id                 = module.spoke_vnet.subnets["aks_nodes"].resource_id
  network_security_group_id = azurerm_network_security_group.aks_nodes.id
}

# VNet Peering is configured from hub side (hub-to-spoke and spoke-to-hub)
# See hub-eastus/main.tf for peering resources

# AKS Cluster with Azure Verified Module
module "aks_cluster" {
  source  = "Azure/avm-res-containerservice-managedcluster/azurerm"
  version = "~> 0.3"

  name      = var.aks_cluster_name
  location  = var.location
  parent_id = azurerm_resource_group.aks_spoke.id

  # Cluster configuration
  kubernetes_version = var.kubernetes_version

  # SKU configuration
  sku = {
    name = "Base"
    tier = var.aks_sku_tier
  }

  # DNS prefix
  dns_prefix = var.aks_cluster_name

  # Default agent pool (system pool)
  default_agent_pool = {
    name                   = "system"
    vm_size                = var.system_node_pool_size
    count_of               = var.system_node_pool_count
    vnet_subnet_id         = module.spoke_vnet.subnets["aks_nodes"].resource_id
    enable_auto_scaling    = false
    os_disk_size_gb        = 30
    os_type                = "Linux"
    enable_host_encryption = true # Enable host-based encryption
  }

  # Network profile
  network_profile = {
    network_plugin      = var.aks_network_plugin # "azure"
    network_plugin_mode = "overlay"              # Azure CNI Overlay
    network_dataplane   = "cilium"               # Cilium for eBPF performance
    network_policy      = var.aks_network_policy # "cilium" for L7 policies
    pod_cidr            = var.aks_pod_cidr       # 192.168.0.0/16
    service_cidr        = var.aks_service_cidr   # 172.16.0.0/16
    dns_service_ip      = var.aks_dns_service_ip # 172.16.0.10
    load_balancer_sku   = "standard"
    outbound_type       = "userDefinedRouting" # Force through firewall
  }

  # API Server access profile for private cluster
  api_server_access_profile = var.enable_private_cluster ? {
    enable_private_cluster             = true
    enable_private_cluster_public_fqdn = false
  } : null

  # Managed identities
  managed_identities = {
    user_assigned_resource_ids = [
      azurerm_user_assigned_identity.aks_control_plane.id
    ]
  }

  # Kubelet identity profile
  identity_profile = {
    kubeletidentity = {
      user_assigned_identity_id = azurerm_user_assigned_identity.aks_kubelet.id
      client_id                 = azurerm_user_assigned_identity.aks_kubelet.client_id
      object_id                 = azurerm_user_assigned_identity.aks_kubelet.principal_id
    }
  }

  # Azure Policy addon
  addon_profile_azure_policy = var.enable_azure_policy ? {
    enabled = true
  } : null

  # OIDC Issuer profile for workload identity
  oidc_issuer_profile = var.enable_workload_identity ? {
    enabled = true
  } : null

  # Security profile for workload identity
  security_profile = var.enable_workload_identity ? {
    workload_identity = {
      enabled = true
    }
  } : null

  # Container Insights addon
  addon_profile_oms_agent = var.enable_monitoring ? {
    enabled = true
    config = {
      log_analytics_workspace_resource_id = try(
        local.hub_outputs.log_analytics_workspace_id,
        data.azurerm_log_analytics_workspace.hub[0].id
      )
    }
  } : null

  # Additional agent pools
  agent_pools = {
    user = {
      name                = "user"
      vm_size             = var.user_node_pool_size
      count_of            = var.user_node_pool_count
      vnet_subnet_id      = module.spoke_vnet.subnets["aks_nodes"].resource_id
      enable_auto_scaling = false
      mode                = "User"
      os_disk_size_gb     = 30
      os_type             = "Linux"
      node_labels = {
        workload = "user"
      }
    }
  }

  enable_telemetry = true
  tags             = local.common_tags

  depends_on = [
    azurerm_subnet_route_table_association.aks_nodes,
    azurerm_subnet_network_security_group_association.aks_nodes
  ]
}

# ===========================
# Azure Container Registry
# ===========================

module "acr" {
  source  = "Azure/avm-res-containerregistry-registry/azurerm"
  version = "~> 0.3"

  name                = "acr${var.environment}${local.location_code}${random_string.acr_suffix.result}"
  location            = var.location
  resource_group_name = azurerm_resource_group.aks_spoke.name

  sku = "Premium" # Required for private endpoints

  # Private endpoint configuration
  private_endpoints = {
    acr_private_endpoint = {
      name                            = "pe-acr-${var.environment}-${local.location_code}"
      subnet_resource_id              = module.spoke_vnet.subnets["management"].resource_id
      private_dns_zone_resource_ids   = [try(local.hub_outputs.private_dns_zone_ids["privatelink.azurecr.io"], "")]
      private_service_connection_name = "psc-acr-${var.environment}-${local.location_code}"
    }
  }

  # Grant AKS kubelet identity pull access
  role_assignments = {
    aks_pull = {
      role_definition_id_or_name = "AcrPull"
      principal_id               = azurerm_user_assigned_identity.aks_kubelet.principal_id
    }
  }

  enable_telemetry = true
  tags             = local.common_tags
}

resource "random_string" "acr_suffix" {
  length  = 6
  special = false
  upper   = false
}

# ===========================
# Azure Key Vault
# ===========================

module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "~> 0.9"

  name                = "kv-${var.environment}-${local.location_code}-${random_string.kv_suffix.result}"
  location            = var.location
  resource_group_name = azurerm_resource_group.aks_spoke.name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name = "standard"

  # Enable for AKS workload integration
  enabled_for_deployment          = true
  enabled_for_disk_encryption     = true
  enabled_for_template_deployment = true
  purge_protection_enabled        = true
  soft_delete_retention_days      = 7

  # Network access
  network_acls = {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = []
  }

  # Private endpoint configuration
  private_endpoints = {
    kv_private_endpoint = {
      name                            = "pe-kv-${var.environment}-${local.location_code}"
      subnet_resource_id              = module.spoke_vnet.subnets["management"].resource_id
      private_dns_zone_resource_ids   = [try(local.hub_outputs.private_dns_zone_ids["privatelink.vaultcore.azure.net"], "")]
      private_service_connection_name = "psc-kv-${var.environment}-${local.location_code}"
    }
  }

  # Grant AKS control plane identity access
  role_assignments = {
    aks_secrets_user = {
      role_definition_id_or_name = "Key Vault Secrets User"
      principal_id               = azurerm_user_assigned_identity.aks_control_plane.principal_id
    }
  }

  enable_telemetry = true
  tags             = local.common_tags
}

resource "random_string" "kv_suffix" {
  length  = 6
  special = false
  upper   = false
}

data "azurerm_client_config" "current" {}

# ===========================
# Spoke Jump Box VM
# ===========================

resource "azurerm_network_interface" "spoke_jumpbox" {
  name                = "nic-jumpbox-spoke-${var.location_code}-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.aks_spoke.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = module.spoke_vnet.subnets["management"].resource_id
    private_ip_address_allocation = "Dynamic"
  }

  tags = var.tags
}

resource "azurerm_linux_virtual_machine" "spoke_jumpbox" {
  name                = "vm-jumpbox-spoke-${var.location_code}-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.aks_spoke.name
  size                = "Standard_D2s_v3"
  admin_username      = var.admin_username

  network_interface_ids = [
    azurerm_network_interface.spoke_jumpbox.id,
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
    set -e
    
    # Update system
    apt-get update
    apt-get upgrade -y
    
    # Install Azure CLI
    curl -sL https://aka.ms/InstallAzureCLIDeb | bash
    
    # Install kubectl
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    mv kubectl /usr/local/bin/
    
    # Install Helm
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    
    # Install k9s
    curl -sS https://webinstall.dev/k9s | bash
    
    # Install jq and other tools
    apt-get install -y jq vim curl wget git
    
    echo "Spoke jump box provisioning complete" >> /var/log/jumpbox-setup.log
  EOT
  )

  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.tags, {
    Purpose = "Jump Box - Spoke Management"
  })
}

# Grant jump box VM AKS user role
resource "azurerm_role_assignment" "jumpbox_aks_user" {
  scope                = module.aks_cluster.resource_id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = azurerm_linux_virtual_machine.spoke_jumpbox.identity[0].principal_id
}

# ===========================
# AKS Diagnostic Settings
# ===========================

resource "azurerm_monitor_diagnostic_setting" "aks" {
  count = try(local.hub_outputs.log_analytics_workspace_id, null) != null ? 1 : 0

  name                       = "diag-aks-${var.environment}-${local.location_code}"
  target_resource_id         = module.aks_cluster.resource_id
  log_analytics_workspace_id = local.hub_outputs.log_analytics_workspace_id

  enabled_log {
    category = "kube-apiserver"
  }

  enabled_log {
    category = "kube-controller-manager"
  }

  enabled_log {
    category = "kube-scheduler"
  }

  enabled_log {
    category = "kube-audit"
  }

  enabled_log {
    category = "cluster-autoscaler"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
