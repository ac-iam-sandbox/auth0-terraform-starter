output "flow_ids" {
  description = "Map of logical name to flow ID"
  value       = { for k, v in auth0_flow.this : k => v.id }
}

output "flow_names" {
  description = "Map of logical name to flow name"
  value       = { for k, v in auth0_flow.this : k => v.name }
}
