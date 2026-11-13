###############################################################################
# Observability: what Datadog needs to show a load test.
#
#   - The percentiles of the service's three duration distributions
#   - The load test dashboard
#
# Independent of the Azure stacks: it outlives `mise run down`, so the dashboard
# of a destroyed configuration can still be screenshotted and exported. The
# metrics themselves come from node/metrics.js (DogStatsD on each VMSS instance)
# and from Artillery's publish-metrics plugin (perf/*.yaml).
###############################################################################

locals {
  # node/metrics.js sends these as DogStatsD distributions, so Datadog aggregates
  # the samples of every node before computing a percentile. Without
  # include_percentiles, only count/sum/min/max/avg exist and the dashboard's
  # p50/p95 queries return nothing.
  #
  # `tags` is the allow-list of tags the metric can be queried by: the agent adds
  # `host`, metrics.js adds the rest. A tag missing here can't be used in a query.
  distributions = {
    "exchange.http.duration"            = ["host", "route"]
    "exchange.exchange.duration"        = ["host"]
    "exchange.arca.validation.duration" = ["host"]
  }
}

resource "datadog_metric_tag_configuration" "distribution" {
  for_each = local.distributions

  metric_name         = each.key
  metric_type         = "distribution"
  tags                = each.value
  include_percentiles = true
}

# Kept as the JSON Datadog exports, so the file in this stack and the export that
# goes with each screenshot (evidencia/<case>/) can be diffed against each other.
resource "datadog_dashboard_json" "load_test" {
  dashboard = file("${path.module}/dashboards/load-test.json")

  # The queries need the percentiles to exist.
  depends_on = [datadog_metric_tag_configuration.distribution]
}
