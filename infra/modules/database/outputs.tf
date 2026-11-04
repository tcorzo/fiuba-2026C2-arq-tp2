output "url" {
  description = "Connection URL of the exchange database, reachable only from inside the VNet. Holds the admin password."
  # verify-full: Azure requires TLS, and the server's certificate chains to a root
  # that Node trusts by default and names this FQDN.
  value     = "postgres://${azurerm_postgresql_flexible_server.this.administrator_login}:${random_password.admin.result}@${azurerm_postgresql_flexible_server.this.fqdn}:5432/${azurerm_postgresql_flexible_server_database.exchange.name}?sslmode=verify-full"
  sensitive = true
}

output "fqdn" {
  description = "FQDN of the server. It resolves only inside the VNet."
  value       = azurerm_postgresql_flexible_server.this.fqdn
}
