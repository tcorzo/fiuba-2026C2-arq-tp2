output "lb_fqdn" {
  description = "Public DNS name of the load balancer: the service's URL."
  value       = azurerm_public_ip.lb.fqdn
}

output "vmss_name" {
  description = "Name of the scale set, as ansible/update_vmss_inventory.sh queries it."
  value       = azurerm_linux_virtual_machine_scale_set.this.name
}
