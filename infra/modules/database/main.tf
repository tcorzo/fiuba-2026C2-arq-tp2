###############################################################################
# The service's store: Azure Database for PostgreSQL Flexible Server, reachable
# only from inside the VNet (delegated subnet + private DNS zone).
###############################################################################

# Server names are global (<name>.postgres.database.azure.com): a random suffix
# avoids a collision with another subscription's server.
resource "random_string" "name" {
  length  = 10
  lower   = true
  upper   = false
  special = false
  numeric = false
}

# Letters and digits only: the password goes into a connection URL unescaped.
resource "random_password" "admin" {
  length  = 32
  special = false
}

# The server's FQDN resolves through this zone, so only the VNet can resolve it.
# A VNet-integrated server requires a zone whose name ends in
# .postgres.database.azure.com.
resource "azurerm_private_dns_zone" "this" {
  name                = "arvault.private.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  name                  = "arvault_postgres_dns_link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = var.vnet_id
}

# No prevent_destroy: `mise run down` destroys foundation after every session,
# because the server is billed by the hour. seed.js reloads the initial state.
# tflint-ignore: azurerm_resources_missing_prevent_destroy
resource "azurerm_postgresql_flexible_server" "this" {
  name                = "arvault-${random_string.name.result}"
  resource_group_name = var.resource_group_name
  location            = var.location

  # Same major version as tp1's postgres:18 image.
  version  = "18"
  sku_name = "B_Standard_B1ms"

  storage_mb            = 32768
  backup_retention_days = 7

  delegated_subnet_id           = var.subnet_id
  private_dns_zone_id           = azurerm_private_dns_zone.this.id
  public_network_access_enabled = false

  administrator_login    = "arvault"
  administrator_password = random_password.admin.result

  # The server can't be created until the zone resolves inside the VNet.
  depends_on = [azurerm_private_dns_zone_virtual_network_link.this]

  lifecycle {
    # Azure picks the availability zone when the zone is not set. Without this,
    # every later plan would try to move the server back to no zone.
    ignore_changes = [zone]
  }
}

# tflint-ignore: azurerm_resources_missing_prevent_destroy
resource "azurerm_postgresql_flexible_server_database" "exchange" {
  name      = "exchange"
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}
