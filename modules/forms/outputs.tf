output "form_ids" {
  description = "Map of logical name to form ID"
  value       = { for k, v in auth0_form.this : k => v.id }
}

output "form_names" {
  description = "Map of logical name to form name"
  value       = { for k, v in auth0_form.this : k => v.name }
}
