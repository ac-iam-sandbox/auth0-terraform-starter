output "id" {
  value = auth0_email_provider.this.id
}

output "action_id" {
  description = "Custom email provider action ID (null if not using custom provider)"
  value       = length(auth0_action.email_provider) > 0 ? auth0_action.email_provider[0].id : null
}
