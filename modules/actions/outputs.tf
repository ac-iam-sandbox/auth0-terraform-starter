output "action_ids" {
  description = "Map of logical name to action ID"
  value       = { for k, v in auth0_action.this : k => v.id }
}

output "action_names" {
  description = "Map of logical name to action name"
  value       = { for k, v in auth0_action.this : k => v.name }
}

output "trigger_bindings" {
  description = "Triggers that have actions bound"
  value       = keys(local.triggers_with_actions)
}
