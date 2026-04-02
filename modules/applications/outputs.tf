output "client_ids" {
  description = "Map of logical name to Auth0 client ID"
  value       = { for k, v in auth0_client.this : k => v.client_id }
}

output "client_names" {
  description = "Map of logical name to Auth0 client name"
  value       = { for k, v in auth0_client.this : k => v.name }
}

output "app_types" {
  description = "Map of logical name to app type"
  value       = { for k, v in auth0_client.this : k => v.app_type }
}
