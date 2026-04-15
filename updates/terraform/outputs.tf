output "client_ids" {
  description = "Map of client key to Auth0 client ID"
  value       = module.clients.client_map
}

output "action_ids" {
  description = "Map of action key to Auth0 action ID"
  value       = module.actions.action_map
}

output "action_module_ids" {
  description = "Map of action module key to { id, version_id }"
  value       = module.action_modules.module_map
}

output "flow_ids" {
  description = "Map of flow key to Auth0 flow ID"
  value       = module.flows.flow_map
}

output "form_ids" {
  description = "Map of form key to Auth0 form ID"
  value       = module.forms.form_map
}
