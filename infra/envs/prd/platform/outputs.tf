output "lb_fqdn" {
  description = "Public DNS name of the load balancer: the service's URL. perf/run.sh reads it."
  value       = module.app.lb_fqdn
}

output "vmss_name" {
  description = "Name of the VM Scale Set."
  value       = module.app.vmss_name
}

# The Node app's runtime settings. ansible/deploy.sh writes this object, as JSON, to
# node/config.local.json (gitignored) before zipping the app, and node/config.js reads
# it. A new setting is a new key here, with the matching key in node/config.js.
# Sensitive: databaseUrl holds the database password. `terraform output -json
# app_config`, which deploy.sh runs, still prints it.
output "app_config" {
  description = "Runtime settings of the Node app, written to node/config.local.json on deploy."
  value = {
    arcaUri     = local.foundation.arca_uri
    databaseUrl = local.foundation.database_url
  }
  sensitive = true
}
