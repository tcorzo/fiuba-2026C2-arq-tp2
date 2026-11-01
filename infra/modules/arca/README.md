# `arca` module

The mock of ARCA's external API: the course's `arqsoft/arca:1.0.0` image on Azure
Container Instances, with 0.5 vCPU and 0.5 GiB. It has a private IP only, on port 8080,
so only the VNet can reach it.

A `local-exec` provisioner writes the URI into `node/config.js` (`arcaUri`) under
`repo_root` with `sed`, leaving a `config.js.bak` behind. Issue #1 tracks replacing it.

## Usage

```hcl
module "arca" {
  source = "../../../modules/arca"

  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  subnet_id           = module.network.container_subnet_id
  dockerhub_username  = var.dockerhub_username
  dockerhub_token     = var.dockerhub_token
  repo_root           = local.repo_root
}
```
