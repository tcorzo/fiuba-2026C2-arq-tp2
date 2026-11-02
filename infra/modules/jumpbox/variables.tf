variable "resource_group_name" {
  description = "Resource group the jumpbox is created in."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "subnet_id" {
  description = "Subnet the jumpbox NIC joins."
  type        = string
}

variable "nsg_id" {
  description = "NSG attached to the jumpbox NIC. It must allow inbound SSH."
  type        = string
}

variable "ssh_public_key" {
  description = "Public key authorized for azureuser."
  type        = string
}

variable "vm_size" {
  description = "VM SKU."
  type        = string
}

variable "image" {
  description = "Marketplace image of the OS disk."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
}
