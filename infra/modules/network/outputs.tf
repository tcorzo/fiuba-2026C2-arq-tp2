output "vnet_id" {
  description = "The VNet. The database module links its private DNS zone to it."
  value       = azurerm_virtual_network.this.id
}

output "database_subnet_id" {
  description = "Subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers."
  value       = azurerm_subnet.database.id
}

output "vmss_subnet_id" {
  description = "Subnet for the app's VM Scale Set. vmss_http_sg is attached to it."
  value       = azurerm_subnet.vmss.id
}

output "jumpbox_subnet_id" {
  description = "Subnet for the jumpbox."
  value       = azurerm_subnet.jumpbox.id
}

output "container_subnet_id" {
  description = "Subnet delegated to Azure Container Instances."
  value       = azurerm_subnet.container.id
}

output "ssh_nsg_id" {
  description = "NSG allowing inbound SSH. Attached to the jumpbox NIC by the jumpbox module."
  value       = azurerm_network_security_group.ssh.id
}
