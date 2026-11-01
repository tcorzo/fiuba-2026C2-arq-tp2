output "lb_fqdn" {
  description = "Public DNS name of the load balancer: the service's URL."
  value       = module.app.lb_fqdn
}

output "vmss_name" {
  description = "Name of the VM Scale Set."
  value       = module.app.vmss_name
}
