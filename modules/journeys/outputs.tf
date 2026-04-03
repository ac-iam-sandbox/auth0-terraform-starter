output "vault_connection_ids" {
  value = { for k, v in auth0_flow_vault_connection.this : k => v.id }
}

output "flow_ids" {
  value = { for k, v in auth0_flow.this : k => v.id }
}

output "form_ids" {
  value = { for k, v in auth0_form.this : k => v.id }
}
