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

  # Merge secrets from three sources:
  #   1. secrets_config  — static per-env values from env YAML
  #   2. secrets_pipeline — injected via TF_VAR_secrets_json
  #   3. form_refs        — auto-resolved form IDs from the forms module
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
      },
      {
        for ref in lookup(v, "form_refs", []) :
        ref.secret_name => var.form_ids[ref.form_key]
      }
    )
  }

  # Whether testing override is active (for safety check).
  testing_active = {
    for k, v in local.active : k => (
      lookup(v, "testing", null) != null
      && contains(lookup(lookup(v, "testing", {}), "envs", []), var.environment)
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

  lifecycle {
    precondition {
      condition     = !(contains(["val", "prod"], var.environment) && local.testing_active[each.key])
      error_message = "Action '${each.key}': val and prod must not resolve testing artifacts. Promote by overwriting main.js and removing the testing block."
    }
    prevent_destroy = true
  }
}

# Trigger bindings - sorted by 'order' field from YAML manifest.
# Actions sharing a trigger are bound in ascending order value.
locals {
  triggers = distinct([for k, v in local.active : v.trigger])
  actions_by_trigger = {
    for trigger in local.triggers : trigger => [
      for pair in sort([
        for k, v in local.active : format("%04d|%s", lookup(v, "order", 9999), k)
        if v.trigger == trigger
        ]) : {
        key  = element(split("|", pair), 1)
        name = local.active[element(split("|", pair), 1)].name
      }
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
