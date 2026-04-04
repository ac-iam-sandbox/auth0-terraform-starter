output "client_map" {
  description = "Map of client key to client_id — share M2M client_ids with the grants team"
  value       = { for k, v in auth0_client.this : k => v.client_id }
}
