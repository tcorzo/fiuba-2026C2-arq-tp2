variable "azure_sid" {
  description = "Azure subscription ID."
  type        = string
  sensitive   = true
}

variable "os_publisher" {
  description = "Publisher of the instances' OS image."
  type        = string
  default     = "Canonical"
}

variable "os_offer" {
  description = "Offer of the instances' OS image."
  type        = string
  default     = "ubuntu-24_04-lts"
}

variable "os_sku" {
  description = "SKU of the instances' OS image."
  type        = string
  default     = "server"
}

variable "os_version" {
  description = "Version of the instances' OS image."
  type        = string
  default     = "latest"
}

variable "machine_sku" {
  description = "VM size of each scale set instance."
  type        = string
  default     = "Standard_F1als_v7"
}
