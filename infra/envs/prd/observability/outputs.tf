output "dashboard_url" {
  description = "URL of the load test dashboard."
  value       = "https://app.${var.datadog_site}${datadog_dashboard_json.load_test.url}"
}
