output "fqdn" {
  description = "Public DNS name of the jumpbox."
  value       = azurerm_public_ip.this.fqdn
}
