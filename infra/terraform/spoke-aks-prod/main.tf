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
    enable_host_encryption = true  # Enable host-based encryption
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
