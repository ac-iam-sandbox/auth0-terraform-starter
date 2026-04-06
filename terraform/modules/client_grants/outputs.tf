output "grant_map" {
  value = { for k, v in auth0_client_grant.this : k => v.id }
}
