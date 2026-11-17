###############################################################################
# Load balancer: public IP, frontend, backend pool, probe and the 443 → 3443
# and 80 → 3080 rules
###############################################################################

# The ports the Node process listens on. app_config hands them to the app, so
# the LB rules and the listeners cannot drift apart.
locals {
  https_backend_port    = 3443
  redirect_backend_port = 3080
}

resource "random_string" "lb_dns_label" {
  length  = 10
  lower   = true
  upper   = false
  special = false
  numeric = false
}

resource "azurerm_public_ip" "lb" {
  name                = "lb_public_ip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = random_string.lb_dns_label.result
}

resource "azurerm_lb" "this" {
  name                = "tp2_lb"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                       = "tp2_lb_public_ip"
    public_ip_address_id       = azurerm_public_ip.lb.id
    private_ip_address_version = "IPv4"
  }
}

# The probe checks the HTTPS port: an instance whose TLS listener is down
# leaves the pool, even if the redirect listener still answers.
resource "azurerm_lb_probe" "this" {
  name            = "lb_probe"
  loadbalancer_id = azurerm_lb.this.id
  port            = local.https_backend_port
}

# The LB is layer 4: it forwards TCP and terminates no TLS. The Node process
# terminates it (H-38). pm2 runs the app as azureuser, which cannot bind ports
# below 1024, so the LB maps the standard ports to unprivileged ones.
resource "azurerm_lb_rule" "https" {
  loadbalancer_id                = azurerm_lb.this.id
  name                           = "HTTPSFwd"
  protocol                       = "Tcp"
  frontend_port                  = 443
  backend_port                   = local.https_backend_port
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.this.id]
  probe_id                       = azurerm_lb_probe.this.id
  frontend_ip_configuration_name = azurerm_lb.this.frontend_ip_configuration[0].name
}

# Plain HTTP reaches only the listener that answers 308 to HTTPS.
resource "azurerm_lb_rule" "http" {
  loadbalancer_id                = azurerm_lb.this.id
  name                           = "HTTPFwd"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = local.redirect_backend_port
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.this.id]
  probe_id                       = azurerm_lb_probe.this.id
  frontend_ip_configuration_name = azurerm_lb.this.frontend_ip_configuration[0].name
}

resource "azurerm_lb_backend_address_pool" "this" {
  loadbalancer_id = azurerm_lb.this.id
  name            = "lb_backend_address_pool"
}

###############################################################################
# VM Scale Set running the Node app. Ansible installs the software afterwards.
###############################################################################

resource "azurerm_linux_virtual_machine_scale_set" "this" {
  name                = "tp2vmss"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.vm_size
  instances           = var.instances
  admin_username      = "azureuser"
  depends_on          = [azurerm_lb_rule.https, azurerm_lb_rule.http]
  upgrade_mode        = "Automatic"

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.ssh_public_key
  }

  source_image_reference {
    publisher = var.image.publisher
    offer     = var.image.offer
    sku       = var.image.sku
    version   = var.image.version
  }

  os_disk {
    storage_account_type = "StandardSSD_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name    = "node_nic"
    primary = true

    ip_configuration {
      name                                   = "node_nic_config"
      primary                                = true
      subnet_id                              = var.subnet_id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.this.id]
    }
  }
}
