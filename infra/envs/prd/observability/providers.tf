# The API and application keys come from DD_API_KEY and DD_APP_KEY, sensitive
# environment variables of the workspace: they never appear in this repository, in a
# plan or in the state. Only the site is a Terraform variable.
provider "datadog" {
  # The site follows the keys' account. A wrong site fails with 403, not silently
  # like the agent or Artillery do.
  api_url = "https://api.${var.datadog_site}/"
}
