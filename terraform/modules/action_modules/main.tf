# https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/action_module

locals {
  # Filter by environments list. No list = all environments.
  active = {
    for k, v in var.definitions : k => v
    if lookup(v, "environments", null) == null || contains(v.environments, var.environment)
  }

  resolved_code = {
    for k, v in local.active : k => (
      lookup(v, "testing", null) != null
      && contains(lookup(lookup(v, "testing", {}), "envs", []), var.environment)
    ) ? v.testing.file : v.code
  }

  resolved_secrets = {
    for k, v in local.active : k => merge(
      {
        for secret_name in lookup(v, "secrets_config", []) :
        secret_name => var.env_config[k][secret_name]
        if lookup(var.env_config, k, null) != null
      },
      {
        for secret_name in lookup(v, "secrets_pipeline", []) :
        secret_name => var.secrets[secret_name]
      }
    )
  }
}

resource "auth0_action_module" "this" {
  for_each = local.active

  name    = each.value.name
  publish = lookup(each.value, "publish", true)
  code    = file("${path.root}/action_modules/${each.key}/${local.resolved_code[each.key]}")

  dynamic "dependencies" {
    for_each = lookup(each.value, "dependencies", {})
    content {
      name    = dependencies.key
      version = dependencies.value
    }
  }

  dynamic "secrets" {
    for_each = local.resolved_secrets[each.key]
    content {
      name  = secrets.key
      value = secrets.value
    }
  }
}
