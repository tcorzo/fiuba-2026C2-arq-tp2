variable "azure_sid" {
  description = "Azure subscription ID."
  type        = string
  sensitive   = true
}

variable "dockerhub_username" {
  description = "Docker Hub user for pulling the ARCA image."
  type        = string
  sensitive   = true
}

variable "dockerhub_token" {
  description = "Docker Hub access token (Public Repo Read-only is enough)."
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Azure region for every resource of the TP. eastus2 or westus2 recommended."
  type        = string
  default     = "eastus2"
}

variable "ssh_key_group_name" {
  description = "Resource group of the pre-existing SSH key pair."
  type        = string
  default     = "keys"
}

variable "ssh_key_name" {
  description = "Name of the pre-existing SSH key pair in Azure."
  type        = string
  default     = "ssh_key"
}

variable "os_publisher" {
  description = "Publisher of the jumpbox's OS image."
  type        = string
  default     = "Canonical"
}

variable "os_offer" {
  description = "Offer of the jumpbox's OS image."
  type        = string
  default     = "ubuntu-24_04-lts"
}

variable "os_sku" {
  description = "SKU of the jumpbox's OS image."
  type        = string
  default     = "server"
}

variable "os_version" {
  description = "Version of the jumpbox's OS image."
  type        = string
  default     = "latest"
}

variable "machine_sku" {
  description = "VM size of the jumpbox."
  type        = string
  default     = "Standard_B1s"
}
