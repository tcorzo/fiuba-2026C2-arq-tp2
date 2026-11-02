# `arca` module

The mock of ARCA's external API: the course's `arqsoft/arca:1.0.0` image on Azure
Container Instances, with 0.5 vCPU and 0.5 GiB. It has a private IP only, on port 8080,
so only the VNet can reach it.

The module exposes the URI as the `uri` output. The `platform` stack passes it to the app
through its `app_config` output, and `ansible/deploy.sh` writes that output to
`node/config.local.json` (gitignored) before zipping the app.

## Usage

```hcl
module "arca" {
  source = "../../../modules/arca"

  resource_group_name = data.azurerm_resource_group.this.name
  location            = var.region
  subnet_id           = module.network.container_subnet_id
  dockerhub_username  = var.dockerhub_username
  dockerhub_token     = var.dockerhub_token
}
```
