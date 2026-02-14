output "resource_group_name" {
  description = "Spoke resource group name"
  value       = local.spoke_rg_name
}

output "spoke_vnet_id" {
  description = "Spoke VNet resource ID"
  value       = local.spoke_vnet_id
}

output "spoke_vnet_name" {
  description = "Spoke VNet name"
  value       = local.spoke_vnet_name
}

output "spoke_subnets" {
  description = "Spoke VNet subnets"
  value = {
    aks_nodes = {
      id               = azurerm_subnet.aks_nodes.id
      address_prefixes = azurerm_subnet.aks_nodes.address_prefixes
    }
    aks_system = {
      id               = azurerm_subnet.aks_system.id
      address_prefixes = azurerm_subnet.aks_system.address_prefixes
    }
    management = {
      id               = azurerm_subnet.management.id
      address_prefixes = azurerm_subnet.management.address_prefixes
    }
  }
}

output "aks_cluster_id" {
  description = "AKS cluster resource ID"
  value       = module.aks_cluster.resource_id
}

output "aks_cluster_name" {
  description = "AKS cluster name"
  value       = module.aks_cluster.name
}

output "aks_cluster_fqdn" {
  description = "AKS cluster FQDN"
  value       = module.aks_cluster.fqdn
}

output "aks_private_fqdn" {
  description = "AKS cluster private FQDN"
  value       = try(module.aks_cluster.private_fqdn, null)
}

output "aks_kube_config_raw" {
  description = "Raw kube config"
  value       = module.aks_cluster.kube_config
  sensitive   = true
}

output "aks_oidc_issuer_url" {
  description = "OIDC issuer URL for workload identity"
  value       = try(module.aks_cluster.oidc_issuer_profile_issuer_url, null)
}

output "aks_control_plane_identity_id" {
  description = "Control plane managed identity ID"
  value       = azurerm_user_assigned_identity.aks_control_plane.id
}

output "aks_kubelet_identity_id" {
  description = "Kubelet managed identity ID"
  value       = azurerm_user_assigned_identity.aks_kubelet.id
}

output "aks_kubelet_identity_client_id" {
  description = "Kubelet managed identity client ID"
  value       = azurerm_user_assigned_identity.aks_kubelet.client_id
}

output "acr_id" {
  description = "Azure Container Registry resource ID"
  value       = module.acr.resource_id
}

output "acr_name" {
  description = "Azure Container Registry name"
  value       = module.acr.name
}

output "key_vault_id" {
  description = "Key Vault resource ID"
  value       = module.key_vault.resource_id
}

output "key_vault_name" {
  description = "Key Vault name"
  value       = module.key_vault.name
}

output "spoke_jumpbox_private_ip" {
  description = "Spoke jump box VM private IP address"
  value       = azurerm_network_interface.spoke_jumpbox.private_ip_address
}

output "spoke_jumpbox_id" {
  description = "Spoke jump box VM resource ID"
  value       = azurerm_linux_virtual_machine.spoke_jumpbox.id
}

output "web_app_routing_enabled" {
  description = "Whether Web App Routing (NGINX ingress) add-on is enabled"
  value       = var.enable_web_app_routing
}

output "nginx_internal_lb_ip" {
  description = "Static internal IP address configured for NGINX ingress controller load balancer"
  value       = var.enable_web_app_routing ? var.nginx_internal_lb_ip : null
}

output "nginx_configuration_note" {
  description = "Instructions for configuring NGINX ingress controller with internal load balancer"
  value       = var.enable_web_app_routing ? "After deployment, create a NginxIngressController resource with loadBalancerAnnotations: 'service.beta.kubernetes.io/azure-load-balancer-internal: true' and 'service.beta.kubernetes.io/azure-load-balancer-internal-ip: ${var.nginx_internal_lb_ip}'. See manifests/nginx-internal-controller.yaml for a complete example." : null
}
