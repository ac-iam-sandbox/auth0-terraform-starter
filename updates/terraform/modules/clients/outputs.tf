output "client_map" {
  description = "Map of client key to client_id"
  value       = { for k, v in auth0_client.this : k => v.client_id }
}

output "client_secret_map" {
  description = "Map of client key to client_secret — only for clients with expose_credentials: true"
  value       = { for k, v in auth0_client_credentials.this : k => v.client_secret }
  sensitive   = true
}
