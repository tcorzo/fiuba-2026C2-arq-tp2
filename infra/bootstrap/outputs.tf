output "workspaces" {
  description = "Stack → URL of its HCP Terraform workspace."
  value       = { for stack, ws in tfe_workspace.this : stack => ws.html_url }
}

output "client_id" {
  description = "Client ID of the Entra ID application the remote runs authenticate as."
  value       = azuread_application.hcp_terraform.client_id
}
