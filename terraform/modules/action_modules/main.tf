# https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/action_module
# https://registry.terraform.io/providers/auth0/auth0/latest/docs/data-sources/action_module_versions

locals {
  resolved_code = {
    for k, v in var.definitions : k => (
      lookup(v, "testing", null) != null
      && contains(lookup(lookup(v, "testing", {}), "envs", []), var.environment)
    ) ? v.testing.file : v.code
  }

  # secrets_config values are keys into env_config
  # secrets_pipeline values are keys into var.secrets
  resolved_secrets = {
    for k, v in var.definitions : k => merge(
      {
        for sk, config_key in lookup(v, "secrets_config", {}) :
        sk => var.env_config[config_key]
      },
      {
        for secret_name in lookup(v, "secrets_pipeline", []) :
        secret_name => var.secrets[secret_name]
      }
    )
  }
}

resource "auth0_action_module" "this" {
  for_each = var.definitions

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

data "auth0_action_module_versions" "this" {
  for_each  = var.definitions
  module_id = auth0_action_module.this[each.key].id
}
