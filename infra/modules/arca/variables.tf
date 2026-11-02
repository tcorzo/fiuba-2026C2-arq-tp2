variable "resource_group_name" {
  description = "Resource group the container group is created in."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "subnet_id" {
  description = "Subnet delegated to Microsoft.ContainerInstance/containerGroups."
  type        = string
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
