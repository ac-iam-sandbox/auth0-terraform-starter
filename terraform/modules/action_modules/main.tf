# https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/action_module
# https://registry.terraform.io/providers/auth0/auth0/latest/docs/data-sources/action_module_versions

locals {
  # Resolve code file: testing block → next.js, otherwise → main.js
  resolved_code = {
    for k, v in var.definitions : k => (
      lookup(v, "testing", null) != null
      && contains(lookup(lookup(v, "testing", {}), "envs", []), var.environment)
    ) ? v.testing.file : v.code
  }

  # Build merged secrets map per module: config values (env-resolved) + pipeline secrets
  resolved_secrets = {
    for k, v in var.definitions : k => merge(
      # Config values resolved per environment
      {
        for sk, sv in lookup(v, "secrets_config", {}) :
        sk => lookup(sv, var.environment, lookup(sv, "default", ""))
      },
      # Pipeline secrets
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

# Retrieve published versions — actions reference the latest.
data "auth0_action_module_versions" "this" {
  for_each  = var.definitions
  module_id = auth0_action_module.this[each.key].id
}
