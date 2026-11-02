terraform {
  required_version = "1.17.1"

  # Local state on purpose (terraform.tfstate next to this file, gitignored): this
  # stack creates the HCP Terraform workspaces the other stacks keep their state in,
  # so it can't keep its own state there. One member applies it once. The secrets go
  # to HCP Terraform as write-only values, so the state holds no token; it still
  # holds IDs (tenant, subscription, app): don't commit it.

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.10"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.80"
    }

    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.82.0"
    }
  }
}
