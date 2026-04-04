# https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/flow_vault_connection

resource "auth0_flow_vault_connection" "this" {
  for_each = var.definitions

  app_id = each.value.app_id
  name   = each.value.name

  # Merge three sources: static values + env config values + pipeline secrets
  setup = merge(
    lookup(each.value, "setup_static", {}),
    {
      for sk, config_key in lookup(each.value, "setup_config", {}) :
      sk => var.env_config[config_key]
    },
    {
      for sk, secret_name in lookup(each.value, "setup_secrets", {}) :
      sk => var.secrets[secret_name]
    }
  )

  lifecycle {
    prevent_destroy = true
  }
}
