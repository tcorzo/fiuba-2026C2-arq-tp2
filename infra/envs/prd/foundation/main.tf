###############################################################################
# Environment: production (prd), stack: foundation
#
# What the app tier stands on and doesn't change between test runs:
#
#   - The resource group every resource of the TP lives in
#   - The network: VNet, subnets and NSGs
#   - The jumpbox, the only SSH entry point into the VNet
#   - ARCA, the mock of the external API, on Container Instances
#
# `platform` reads this stack's outputs, so outputs.tf is a contract: renaming or
# removing an output breaks platform's plan. Apply this stack first and destroy it
# last.
###############################################################################

locals {
  # The local-exec provisioners write generated files into the repository
  # (node/config.js, ansible/jumpbox_dns). Issue #1 tracks replacing them.
  repo_root = abspath("${path.root}/../../../..")

  image = {
    publisher = var.os_publisher
    offer     = var.os_offer
    sku       = var.os_sku
    version   = var.os_version
  }
}

resource "azurerm_resource_group" "this" {
  name     = "tp2_resource_group"
  location = var.region
}

# Pre-existing key pair, created by hand in the Azure portal. Not managed here.
data "azurerm_ssh_public_key" "this" {
  name                = var.ssh_key_name
  resource_group_name = var.ssh_key_group_name
}

module "network" {
  source = "../../../modules/network"

  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
}

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

module "arca" {
  source = "../../../modules/arca"

  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  subnet_id           = module.network.container_subnet_id
  dockerhub_username  = var.dockerhub_username
  dockerhub_token     = var.dockerhub_token
  repo_root           = local.repo_root
}
