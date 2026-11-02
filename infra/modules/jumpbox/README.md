# `jumpbox` module

The only SSH entry point into the VNet. Ansible and people reach the VMSS instances
through it with an SSH `ProxyCommand`.

Creates a public IP with a random DNS label, a NIC with the given NSG attached, and a
Linux VM named `jumpbox` (admin user `azureuser`, `Standard_LRS` disk).

The module exposes the public FQDN as the `fqdn` output. The `foundation` stack exposes it
as `jumpbox_fqdn`, which `ansible/update_vmss_inventory.sh` reads with `terraform output`.

## Usage

```hcl
module "jumpbox" {
  source = "../../../modules/jumpbox"

  resource_group_name = data.azurerm_resource_group.this.name
  location            = var.region
  subnet_id           = module.network.jumpbox_subnet_id
  nsg_id              = module.network.ssh_nsg_id
  ssh_public_key      = data.azurerm_ssh_public_key.this.public_key
  vm_size             = var.machine_sku
  image               = local.image
}
```
