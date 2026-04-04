# https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/action
# https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/trigger_actions

locals {
  # Resolve code file: testing block → next.js, otherwise → main.js
  resolved_code = {
    for k, v in var.definitions : k => (
      lookup(v, "testing", null) != null
      && contains(lookup(lookup(v, "testing", {}), "envs", []), var.environment)
    ) ? v.testing.file : v.code
  }

  # Build merged secrets map per action: config values (env-resolved) + pipeline secrets
  resolved_secrets = {
    for k, v in var.definitions : k => merge(
      {
        for sk, sv in lookup(v, "secrets_config", {}) :
        sk => lookup(sv, var.environment, lookup(sv, "default", ""))
      },
      {
        for secret_name in lookup(v, "secrets_pipeline", []) :
        secret_name => var.secrets[secret_name]
      }
    )
  }
}

resource "auth0_action" "this" {
  for_each = var.definitions

  name    = each.value.name
  runtime = each.value.runtime
  deploy  = each.value.deploy
  code    = file("${path.root}/actions/${each.key}/${local.resolved_code[each.key]}")

  supported_triggers {
    id      = each.value.trigger
    version = each.value.trigger_version
  }

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

  # Bind action modules — module_id and module_version_id resolved from action_modules output.
  # Terraform creates modules before actions (dependency graph) so version IDs are available.
  dynamic "modules" {
    for_each = lookup(each.value, "modules", [])
    content {
      module_id         = var.action_module_outputs[modules.value.module_key].id
      module_version_id = var.action_module_outputs[modules.value.module_key].version_id
    }
  }
}

# Trigger bindings — order matters.
# Actions are grouped by trigger. The order of actions blocks defines execution order.
# https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/trigger_actions
locals {
  triggers = distinct([for k, v in var.definitions : v.trigger])

  # Preserve insertion order from the YAML by using keys()
  actions_by_trigger = {
    for trigger in local.triggers : trigger => [
      for k in keys(var.definitions) : {
        key  = k
        name = var.definitions[k].name
      } if var.definitions[k].trigger == trigger
    ]
  }
}

resource "auth0_trigger_actions" "this" {
  for_each = local.actions_by_trigger
  trigger  = each.key

  dynamic "actions" {
    for_each = each.value
    content {
      id           = auth0_action.this[actions.value.key].id
      display_name = actions.value.name
    }
  }
}
