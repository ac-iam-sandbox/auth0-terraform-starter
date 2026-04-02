output "vault_connection_ids" {
  description = "Map of logical name to vault connection ID"
  value       = { for k, v in auth0_flow_vault_connection.this : k => v.id }
}

output "vault_connection_names" {
  description = "Map of logical name to vault connection name"
  value       = { for k, v in auth0_flow_vault_connection.this : k => v.name }
}

output "vault_connection_ready" {
  description = "Map of logical name to ready status"
  value       = { for k, v in auth0_flow_vault_connection.this : k => v.ready }
}
