###############################################################################
# Bootstrap: what HCP Terraform needs before the prd stacks can run remotely.
#
#   - One workspace per stack, in the existing project, with remote execution
#     and the stack's directory as working directory
#   - An Entra ID application that the remote runs authenticate as, through
#     dynamic provider credentials (OIDC): no client secret exists anywhere
#   - Contributor on the subscription for that application
#   - The workspaces' variables: Azure auth, subscription, Docker Hub
#
# Apply it once, before the first `terraform init` of a prd stack. Destroying it
# deletes the workspaces and their state: destroy the prd stacks first.
###############################################################################

locals {
  # Stack name → workspace name. Workspace names are unique per organization, so each
  # one is the project's name plus the stack's: <project>-foundation, <project>-platform.
  # Each name is also written, as a literal, in the stack's `cloud` block.
  workspaces = { for stack in ["foundation", "platform"] : stack => "${var.hcp_project}-${stack}" }

  # HCP Terraform signs a token per run phase; Entra ID matches the subject exactly.
  federated_subjects = {
    for pair in setproduct(keys(local.workspaces), ["plan", "apply"]) :
    "${pair[0]}-${pair[1]}" => "organization:${var.hcp_organization}:project:${var.hcp_project}:workspace:${local.workspaces[pair[0]]}:run_phase:${pair[1]}"
  }
}

data "tfe_project" "this" {
  name = var.hcp_project
}

data "azurerm_subscription" "this" {}

data "azuread_client_config" "current" {}

###############################################################################
# Azure identity of the remote runs
###############################################################################

# Owned by whoever created them (the subscription's Owner). ignore_changes keeps a
# later run by someone else from replacing the owners with that person.
resource "azuread_application" "hcp_terraform" {
  display_name = "hcp-terraform-${var.hcp_project}"
  owners       = [data.azuread_client_config.current.object_id]

  lifecycle {
    ignore_changes = [owners]
  }
}

resource "azuread_service_principal" "hcp_terraform" {
  client_id = azuread_application.hcp_terraform.client_id
  owners    = [data.azuread_client_config.current.object_id]

  lifecycle {
    ignore_changes = [owners]
  }
}

resource "azuread_application_federated_identity_credential" "hcp_terraform" {
  for_each = local.federated_subjects

  application_id = azuread_application.hcp_terraform.id
  display_name   = "hcp-terraform-${each.key}"
  description    = "HCP Terraform ${each.value}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://app.terraform.io"
  subject        = each.value
}

# foundation creates the resource group, so the role is on the subscription.
resource "azurerm_role_assignment" "hcp_terraform" {
  scope                = data.azurerm_subscription.this.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.hcp_terraform.object_id
}

###############################################################################
# Workspaces
###############################################################################

resource "tfe_workspace" "this" {
  for_each = local.workspaces

  name              = each.value
  description       = "arVault TP 2, prd: the ${each.key} stack (infra/envs/prd/${each.key})."
  project_id        = data.tfe_project.this.id
  terraform_version = var.terraform_version

  # The stack calls modules from infra/modules, so the CLI must upload the whole
  # repository root. A working directory makes it do so (minus .terraformignore).
  working_directory = "infra/envs/prd/${each.key}"
}

resource "tfe_workspace_settings" "foundation" {
  workspace_id   = tfe_workspace.this["foundation"].id
  execution_mode = "remote"

  # Only platform reads foundation's outputs.
  global_remote_state       = false
  remote_state_consumer_ids = [tfe_workspace.this["platform"].id]
}

resource "tfe_workspace_settings" "platform" {
  workspace_id   = tfe_workspace.this["platform"].id
  execution_mode = "remote"

  global_remote_state       = false
  remote_state_consumer_ids = []
}

###############################################################################
# Workspace variables
###############################################################################

locals {
  # Every workspace authenticates to Azure the same way. None of these is a secret.
  azure_env = {
    TFC_AZURE_PROVIDER_AUTH = "true"
    TFC_AZURE_RUN_CLIENT_ID = azuread_application.hcp_terraform.client_id
    ARM_TENANT_ID           = data.azurerm_subscription.this.tenant_id
  }

  env_variables = merge([
    for stack in keys(local.workspaces) : {
      for key, value in local.azure_env : "${stack}/${key}" => { stack = stack, key = key, value = value }
    }
  ]...)

  # All sensitive. The keys are not, which for_each needs.
  terraform_variables = merge(
    { for stack in keys(local.workspaces) : "${stack}/azure_sid" => var.azure_sid },
    {
      "foundation/dockerhub_username" = var.dockerhub_username
      "foundation/dockerhub_token"    = var.dockerhub_token
    },
  )
}

resource "tfe_variable" "env" {
  for_each = local.env_variables

  workspace_id = tfe_workspace.this[each.value.stack].id
  category     = "env"
  key          = each.value.key
  value        = each.value.value
}

# value_wo is write-only: the secret reaches HCP Terraform but never this stack's
# state or plan. The provider keeps only a hash, and re-sends the value when it changes.
resource "tfe_variable" "terraform" {
  for_each = toset(keys(local.terraform_variables))

  workspace_id = tfe_workspace.this[split("/", each.key)[0]].id
  category     = "terraform"
  key          = split("/", each.key)[1]
  value_wo     = local.terraform_variables[each.key]
  sensitive    = true
}
