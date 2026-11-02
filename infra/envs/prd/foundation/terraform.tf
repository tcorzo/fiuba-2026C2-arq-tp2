terraform {
  # Exact, and the same as mise.toml and the workspace's Terraform version (set by
  # infra/bootstrap): state written by a newer CLI cannot be read by an older one.
  required_version = "1.17.1"

  # State and runs live in HCP Terraform. Runs execute remotely: the CLI uploads the
  # repository root (minus .terraformignore) because the workspace's working directory
  # is infra/envs/prd/foundation. infra/bootstrap creates the workspace, its variables
  # and the Azure identity it authenticates with.
  cloud {
    organization = "gaudi-followers"

    workspaces {
      project = "arvault-prd"
      name    = "arvault-prd-foundation"
    }
  }

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
