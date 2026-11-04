# platform reads these through terraform_remote_state. Renaming or removing one
# breaks platform's plan.

output "resource_group_name" {
  description = "Resource group every resource of the TP lives in. ansible/update_vmss_inventory.sh reads it."
  value       = data.azurerm_resource_group.this.name
}

output "location" {
  description = "Azure region every resource of the TP is created in. Not the resource group's own region."
  value       = var.region
}

output "vmss_subnet_id" {
  description = "Subnet for the app's VM Scale Set."
  value       = module.network.vmss_subnet_id
}

output "ssh_public_key" {
  description = "Public key authorized for azureuser on every VM."
  value       = data.azurerm_ssh_public_key.this.public_key
}

output "jumpbox_fqdn" {
  description = "Public DNS name of the jumpbox."
  value       = module.jumpbox.fqdn
}

output "arca_uri" {
  description = "Base URI of ARCA, reachable only from inside the VNet."
  value       = module.arca.uri
}

output "database_url" {
  description = "Connection URL of the service's PostgreSQL database, reachable only from inside the VNet. Holds the admin password."
  value       = module.database.url
  sensitive   = true
}
