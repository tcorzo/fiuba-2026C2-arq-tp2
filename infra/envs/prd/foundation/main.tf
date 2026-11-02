###############################################################################
# Environment: production (prd), stack: foundation
#
# What the app tier stands on and doesn't change between test runs:
#
#   - The network: VNet, subnets and NSGs
#   - The jumpbox, the only SSH entry point into the VNet
#   - ARCA, the mock of the external API, on Container Instances
#
# `platform` reads this stack's outputs, so outputs.tf is a contract: renaming or
# removing an output breaks platform's plan. Apply this stack first and destroy it
# last. The scripts in ansible/ also read jumpbox_fqdn and resource_group_name with
# `terraform output`.
#
# Every resource is created in var.region, not in the resource group's own region:
# a resource group's region is only where its metadata lives.
###############################################################################

locals {
  image = {
    publisher = var.os_publisher
    offer     = var.os_offer
    sku       = var.os_sku
    version   = var.os_version
  }
}

# The resource group and the team's access to it (group ARQUI-TP2-ADMIN,
# Contributor) are managed by infra/bootstrap, which the subscription's Owner
# applies. Only read here, so destroying this stack empties the resource group
# and keeps it, with the team's access.
data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

# Pre-existing key pair, created by hand in the Azure portal (SSH keys → Create, in
# RG-PRODUCTION, named ssh_key), whose private key is key.pem at the repository root.
# Not managed here: the portal keeps the private key out of Terraform's state.
data "azurerm_ssh_public_key" "this" {
  name                = var.ssh_key_name
  resource_group_name = var.ssh_key_group_name
}

module "network" {
  source = "../../../modules/network"

  resource_group_name = data.azurerm_resource_group.this.name
  location            = var.region
}

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

module "arca" {
  source = "../../../modules/arca"

  resource_group_name = data.azurerm_resource_group.this.name
  location            = var.region
  subnet_id           = module.network.container_subnet_id
  dockerhub_username  = var.dockerhub_username
  dockerhub_token     = var.dockerhub_token
}
