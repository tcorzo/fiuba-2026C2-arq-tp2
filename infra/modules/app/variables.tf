variable "resource_group_name" {
  description = "Resource group the scale set and load balancer are created in."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "subnet_id" {
  description = "Subnet the scale set's NICs join."
  type        = string
}

variable "ssh_public_key" {
  description = "Public key authorized for azureuser."
  type        = string
}

variable "vm_size" {
  description = "VM SKU of each instance."
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
