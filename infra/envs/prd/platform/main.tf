###############################################################################
# Environment: production (prd), stack: platform
#
# The app tier, the part each infrastructure configuration of the TP changes:
#
#   - The public Standard Load Balancer (TCP 80 → 3000)
#   - The VM Scale Set running the Node app
#
# It reads the resource group, the subnet and the SSH key from foundation's
# outputs, so foundation must be applied first. Ansible installs the software on
# the instances after this stack is applied (mise run ansible:setup, app:deploy).
###############################################################################

# foundation's workspace shares its state with this one only (remote state
# sharing, set by infra/bootstrap). Only its outputs are read.
data "terraform_remote_state" "foundation" {
  backend = "remote"

  config = {
    organization = "gaudi-followers"

    workspaces = {
      name = "arvault-prd-foundation"
    }
  }
}

locals {
  foundation = data.terraform_remote_state.foundation.outputs

  image = {
    publisher = var.os_publisher
    offer     = var.os_offer
    sku       = var.os_sku
    version   = var.os_version
  }
}

module "app" {
  source = "../../../modules/app"

  resource_group_name = local.foundation.resource_group_name
  location            = local.foundation.location
  subnet_id           = local.foundation.vmss_subnet_id
  ssh_public_key      = local.foundation.ssh_public_key
  vm_size             = var.machine_sku
  image               = local.image
}
