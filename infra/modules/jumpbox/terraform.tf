terraform {
  required_version = ">= 1.3"

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
