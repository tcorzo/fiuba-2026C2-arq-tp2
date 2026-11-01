terraform {
  # Exact, and the same as mise.toml: state written by a newer CLI cannot be read by
  # an older one.
  required_version = "1.17.1"

  # State is local for now (terraform.tfstate next to this file, gitignored). Moving
  # to HCP Terraform means adding a `cloud` block here.

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.80"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
