# https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/action
# https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/trigger_actions

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

resource "auth0_action" "this" {
  for_each = local.active

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

  dynamic "modules" {
    for_each = lookup(each.value, "modules", [])
    content {
      module_id         = var.action_module_outputs[modules.value.module_key].id
      module_version_id = var.action_module_outputs[modules.value.module_key].version_id
    }
  }
}

# Trigger bindings — only includes active actions.
# YAML order = execution order.
locals {
  triggers = distinct([for k, v in local.active : v.trigger])
  actions_by_trigger = {
    for trigger in local.triggers : trigger => [
      for k in keys(local.active) : {
        key  = k
        name = local.active[k].name
      } if local.active[k].trigger == trigger
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
      display_name = auth0_action.this[actions.value.key].name
    }
  }

  depends_on = [auth0_action.this]
}
