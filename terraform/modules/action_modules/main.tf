# https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/action_module
# https://registry.terraform.io/providers/auth0/auth0/latest/docs/data-sources/action_module_versions

locals {
  # Resolve code file: if testing block exists and current env is listed, use testing file.
  resolved_code = {
    for k, v in var.definitions : k => (
      lookup(v, "testing", null) != null
      && contains(lookup(lookup(v, "testing", {}), "envs", []), var.environment)
    ) ? v.testing.file : v.code
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
    for_each = lookup(each.value, "secrets", [])
    content {
      name  = secrets.value
      value = var.secrets[secrets.value]
    }
  }
}

# Retrieve published versions — always use the latest.
data "auth0_action_module_versions" "this" {
  for_each  = var.definitions
  module_id = auth0_action_module.this[each.key].id
}
