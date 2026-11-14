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

variable "datadog_api_key" {
  description = "Datadog API key, the same as DATADOG_API_KEY. Set on the observability workspace as DD_API_KEY."
  type        = string
  sensitive   = true
}

variable "datadog_app_key" {
  description = "Datadog application key (Organization Settings > Application Keys). Set on the observability workspace as DD_APP_KEY. Managing dashboards needs it; the API key alone only submits data."
  type        = string
  sensitive   = true
}

# No default on purpose, like DATADOG_SITE: keys sent to the wrong site fail.
variable "datadog_site" {
  description = "Datadog site of the keys' account (e.g. us5.datadoghq.com), the same as DATADOG_SITE. Set on the observability workspace."
  type        = string
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
