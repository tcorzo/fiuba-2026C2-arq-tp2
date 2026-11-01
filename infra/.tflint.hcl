# tflint: the Terraform ruleset's recommended preset, plus the azurerm ruleset, which
# knows what each resource accepts (VM sizes, regions, ...). It reads the configuration
# only, without calling Azure.
#
# mise.toml points TFLINT_CONFIG_FILE here, so this file governs every stack and module.

config {
  # Local modules are read from disk, so a stack's call into ../../../modules is
  # checked without `terraform init`.
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}
