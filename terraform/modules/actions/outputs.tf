output "action_map" {
  value = { for k, v in auth0_action.this : k => v.id }
}
