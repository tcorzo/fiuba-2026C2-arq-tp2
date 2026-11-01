# `network` module

The VNet and everything that decides where traffic can go.

| Resource | Azure name | Notes |
|---|---|---|
| VNet | `tp2_network` | `10.0.0.0/16` |
| Subnet | `tp2_vmss_subnet` | `10.0.2.0/24`, app instances. `vmss_http_sg` is attached |
| Subnet | `tp2_jumpbox_subnet` | `10.0.3.0/24` |
| Subnet | `tp2_container_subnet` | `10.0.4.0/24`, delegated to Container Instances |
| NSG | `ssh_sg` | Allows TCP 22 from anywhere. The jumpbox module attaches it to its NIC |
| NSG | `vmss_http_sg` | Allows TCP 3000 from anywhere |

The address plan is fixed on purpose: there are no inputs for it.

## Usage

```hcl
module "network" {
  source = "../../../modules/network"

  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
}
```
