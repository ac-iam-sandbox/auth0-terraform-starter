output "module_ids" {
  description = "Map of logical name to action module ID"
  value       = { for k, v in auth0_action_module.this : k => v.id }
}

output "module_names" {
  description = "Map of logical name to action module name"
  value       = { for k, v in auth0_action_module.this : k => v.name }
}

output "module_version_ids" {
  description = "Map of logical name to latest published version ID"
  value       = { for k, v in auth0_action_module.this : k => v.version_id }
}

output "module_version_numbers" {
  description = "Map of logical name to latest published version number"
  value       = { for k, v in auth0_action_module.this : k => v.latest_version_number }
}

output "all_changes_published" {
  description = "Map of logical name to whether all drafts are published"
  value       = { for k, v in auth0_action_module.this : k => v.all_changes_published }
}
