terraform {
  # Exact, and the same as mise.toml and the workspace's Terraform version (set by
  # infra/bootstrap): state written by a newer CLI cannot be read by an older one.
  required_version = "1.17.1"

  # State and runs live in HCP Terraform, like the other prd stacks. This workspace
  # has no Azure identity: it only talks to Datadog, with the keys infra/bootstrap
  # sets as sensitive environment variables (DD_API_KEY, DD_APP_KEY).
  cloud {
    organization = "gaudi-followers"

    workspaces {
      project = "arvault-prd"
      name    = "arvault-prd-observability"
    }
  }

  required_providers {
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 4.30"
    }
  }
}
