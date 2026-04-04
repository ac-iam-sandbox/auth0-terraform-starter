output "client_ids" {
  description = "Map of client key to Auth0 client ID"
  value       = module.clients.client_map
}

output "action_ids" {
  description = "Map of action key to Auth0 action ID"
  value       = module.actions.action_map
}

output "flow_ids" {
  description = "Map of flow key to Auth0 flow ID"
  value       = module.flows.flow_map
}
