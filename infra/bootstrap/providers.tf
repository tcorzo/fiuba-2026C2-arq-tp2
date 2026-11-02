# Both Azure providers use the `az login` session of whoever applies this stack. That
# person must be able to register applications in the tenant and assign roles on the
# subscription (Owner of the subscription is enough).
provider "azurerm" {
  subscription_id = var.azure_sid

  # This stack only reads the subscription and assigns a role (Microsoft.Authorization,
  # always registered). Registering the ~60 providers azurerm registers by default
  # would demand `*/register/action` for nothing.
  resource_provider_registrations = "none"

  features {}
}

provider "azuread" {}

# Uses the token `terraform login` stored for app.terraform.io, or TFE_TOKEN.
provider "tfe" {
  organization = var.hcp_organization
}
