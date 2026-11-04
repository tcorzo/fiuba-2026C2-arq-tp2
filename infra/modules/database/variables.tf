variable "resource_group_name" {
  description = "Resource group the server and its private DNS zone are created in."
  type        = string
}

variable "location" {
  description = "Azure region. Must be the VNet's region."
  type        = string
}

variable "vnet_id" {
  description = "VNet linked to the private DNS zone, so its hosts resolve the server's FQDN."
  type        = string
}

variable "subnet_id" {
  description = "Subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers."
  type        = string
}
