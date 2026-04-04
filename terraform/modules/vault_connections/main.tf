# https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/flow_vault_connection

locals {
  # Filter by environments list. No list = all environments.
  active = {
    for k, v in var.definitions : k => v
    if lookup(v, "environments", null) == null || contains(v.environments, var.environment)
  }
}

resource "auth0_flow_vault_connection" "this" {
  for_each = local.active

  app_id = each.value.app_id
  name   = each.value.name

  setup = merge(
    lookup(each.value, "setup_static", {}),
    {
      for config_key in lookup(each.value, "setup_config", []) :
      config_key => var.env_config[each.key][config_key]
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
