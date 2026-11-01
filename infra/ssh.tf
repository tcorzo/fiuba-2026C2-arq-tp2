data "azurerm_ssh_public_key" "ssh_key" {
  name                = var.ssh_key_name
  resource_group_name = var.ssh_key_group_name
}