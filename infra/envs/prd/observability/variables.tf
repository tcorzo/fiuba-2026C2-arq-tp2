variable "datadog_site" {
  description = "Datadog site of the account, without the app. prefix: datadoghq.com, us5.datadoghq.com, ... The same value as DATADOG_SITE."
  type        = string

  validation {
    condition     = !startswith(var.datadog_site, "app.") && !startswith(var.datadog_site, "http")
    error_message = "Use the bare site (e.g. us5.datadoghq.com), without https:// or the app. prefix."
  }
}
