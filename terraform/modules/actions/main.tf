# https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/action
# https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/trigger_actions

locals {
  # Resolve code file: if testing block exists and current env is listed, use testing file.
  resolved_code = {
    for k, v in var.definitions : k => (
      lookup(v, "testing", null) != null
      && contains(lookup(lookup(v, "testing", {}), "envs", []), var.environment)
    ) ? v.testing.file : v.code
  }
}

resource "auth0_action" "this" {
  for_each = var.definitions

  name    = each.key
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
    for_each = lookup(each.value, "secrets", [])
    content {
      name  = secrets.value
      value = var.secrets[secrets.value]
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

# Group actions by trigger for binding.
locals {
  triggers = distinct([for k, v in var.definitions : v.trigger])
  actions_by_trigger = {
    for trigger in local.triggers : trigger => [
      for k, v in var.definitions : { key = k, name = k } if v.trigger == trigger
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
