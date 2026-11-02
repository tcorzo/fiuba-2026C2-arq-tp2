variable "azure_sid" {
  description = "Azure subscription ID every stack deploys into."
  type        = string
  sensitive   = true
}

variable "dockerhub_username" {
  description = "Docker Hub user for pulling the ARCA image. Set on the foundation workspace."
  type        = string
  sensitive   = true
}

variable "dockerhub_token" {
  description = "Docker Hub access token (Public Repo Read-only is enough). Set on the foundation workspace."
  type        = string
  sensitive   = true
}

variable "resource_group_name" {
  description = "Resource group the prd stacks deploy into. Its name is also the default of foundation's resource_group_name."
  type        = string
  default     = "RG-PRODUCTION"
}

variable "resource_group_location" {
  description = "Region of the resource group's metadata. Changing it replaces the resource group. The resources inside use foundation's region."
  type        = string
  default     = "eastus"
}

variable "team_group_name" {
  description = "Entra ID security group of the team. It gets Contributor on the resource group."
  type        = string
  default     = "ARQUI-TP2-ADMIN"
}

# The two names below are repeated, as literals, in each stack's `cloud` block and in
# platform's terraform_remote_state: Terraform doesn't accept variables there.
variable "hcp_organization" {
  description = "HCP Terraform organization."
  type        = string
  default     = "gaudi-followers"
}

variable "hcp_project" {
  description = "HCP Terraform project the workspaces belong to. It must already exist."
  type        = string
  default     = "arvault-prd"
}

variable "terraform_version" {
  description = "Terraform version of the remote runs. The same as required_version in each stack and mise.toml."
  type        = string
  default     = "1.17.1"
}
