# `jumpbox` module

The only SSH entry point into the VNet. Ansible and people reach the VMSS instances
through it with an SSH `ProxyCommand`.

Creates a public IP with a random DNS label, a NIC with the given NSG attached, and a
Linux VM named `jumpbox` (admin user `azureuser`, `Standard_LRS` disk).

A `local-exec` provisioner writes the public FQDN to `ansible/jumpbox_dns` under
`repo_root` when the VM is created. Issue #1 tracks replacing it.

## Usage

```hcl
module "jumpbox" {
  source = "../../../modules/jumpbox"

  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  subnet_id           = module.network.jumpbox_subnet_id
  nsg_id              = module.network.ssh_nsg_id
  ssh_public_key      = data.azurerm_ssh_public_key.this.public_key
  vm_size             = var.machine_sku
  image               = local.image
  repo_root           = local.repo_root
}
```
