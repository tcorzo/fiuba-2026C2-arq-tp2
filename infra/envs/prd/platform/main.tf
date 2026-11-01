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

data "terraform_remote_state" "foundation" {
  backend = "local"

  config = {
    path = "${path.root}/../foundation/terraform.tfstate"
  }
}

locals {
  foundation = data.terraform_remote_state.foundation.outputs

  # The local-exec provisioners write generated files into the repository
  # (node/lb_dns, ansible/ddog_api_key). Issue #1 tracks replacing them.
  repo_root = abspath("${path.root}/../../../..")

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
  datadog_key         = var.datadog_key
  repo_root           = local.repo_root
}
