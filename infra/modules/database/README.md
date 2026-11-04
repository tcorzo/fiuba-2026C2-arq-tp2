# `database` module

The service's store: Azure Database for PostgreSQL Flexible Server, with private access
only.

- **Server** `arvault-<random>`: PostgreSQL 18 (tp1 used `postgres:18`),
  `B_Standard_B1ms` (1 vCore, 2 GiB, burstable: it runs on CPU credits), 32 GB of
  storage, 7 days of backups. Azure picks the availability zone, and later plans ignore
  it.
- **Network.** The server lives in the delegated subnet it receives and has no public
  endpoint. Its FQDN resolves through the private DNS zone
  `arvault.private.postgres.database.azure.com`, linked to the VNet, so only hosts in
  the VNet can resolve and reach it.
- **Database** `exchange`, owned by the admin user `arvault`. The password is a
  `random_password` of letters and digits, so it goes into a URL without escaping.

The `url` output (sensitive) is the connection URL with `sslmode=verify-full`: Azure
requires TLS. The `foundation` stack exposes it as `database_url`, and `platform` passes
it to the app through `app_config`.

The tables don't come from Terraform. The app's `seed.js` creates them and loads the
initial state.

## Usage

```hcl
module "database" {
  source = "../../../modules/database"

  resource_group_name = data.azurerm_resource_group.this.name
  location            = var.region
  vnet_id             = module.network.vnet_id
  subnet_id           = module.network.database_subnet_id
}
```
