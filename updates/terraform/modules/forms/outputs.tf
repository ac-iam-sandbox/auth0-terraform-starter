output "form_map" {
  value = { for k, v in auth0_form.this : k => v.id }
}
