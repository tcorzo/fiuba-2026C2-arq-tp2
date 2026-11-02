###############################################################################
# The resource group the prd stacks deploy into, and the team's access to it
#
# Here and not in `foundation`: a resource group foundation created would be
# deleted, with the team's role assignment, on every `destroy`, and recreating
# that assignment would need the HCP Terraform identity to assign roles. This
# stack is applied by the subscription's Owner, who can. `foundation` only reads
# the resource group (data "azurerm_resource_group").
#
# Both were first created by hand in the portal. The import blocks adopt them
# into this stack's state instead of creating new ones; once imported, a later
# apply finds them in state and the blocks do nothing.
###############################################################################

data "azuread_group" "team" {
  display_name     = var.team_group_name
  security_enabled = true
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.resource_group_location

  tags = {
    environment = "production"
  }
}

resource "azurerm_role_assignment" "team" {
  scope                = azurerm_resource_group.this.id
  role_definition_name = "Contributor"
  principal_id         = data.azuread_group.team.object_id
}

import {
  to = azurerm_resource_group.this
  id = "${data.azurerm_subscription.this.id}/resourceGroups/${var.resource_group_name}"
}

# A role assignment's ID ends in its name, a GUID Azure generated when it was created
# in the portal: `az role assignment list --resource-group RG-PRODUCTION`.
import {
  to = azurerm_role_assignment.team
  id = "${data.azurerm_subscription.this.id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.Authorization/roleAssignments/9d465f4f-9e57-4178-b712-b69af76dbf7e"
}
