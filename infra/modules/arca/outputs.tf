output "uri" {
  description = "Base URI of the ARCA service, reachable only from inside the VNet."
  value       = "http://${azurerm_container_group.this.ip_address}:8080"
}
