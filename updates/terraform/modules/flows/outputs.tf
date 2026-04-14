output "flow_map" {
  value = { for k, v in auth0_flow.this : k => v.id }
}
