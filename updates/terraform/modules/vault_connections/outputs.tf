output "connection_map" {
  value = { for k, v in auth0_flow_vault_connection.this : k => v.id }
}
