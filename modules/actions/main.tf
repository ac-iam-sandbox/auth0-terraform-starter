# =============================================================================
# Auth0 actions - data-driven via for_each
# =============================================================================
# Creates actions from a map, automatically groups them by trigger, and
# creates deterministic trigger bindings.
#
# SAFETY: prevent_destroy on actions to avoid accidental deletion.
# =============================================================================

resource "auth0_action" "this" {
  for_each = var.actions

  name    = each.value.name
  runtime = each.value.runtime
  deploy  = each.value.deploy
  code    = each.value.code

  supported_triggers {
    id      = each.value.trigger_id
    version = each.value.trigger_version
  }

  dynamic "dependencies" {
    for_each = each.value.dependencies
    content {
      name    = dependencies.value.name
      version = dependencies.value.version
    }
  }

  dynamic "secrets" {
    for_each = each.value.secrets
    content {
      name  = secrets.value.name
      value = secrets.value.value
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Auto-group actions by trigger and create bindings deterministically
locals {
  triggers_with_actions = {
    for trigger_id in distinct([for k, v in var.actions : v.trigger_id if v.bind]) :
    trigger_id => sort([
      for k, v in var.actions : k if v.trigger_id == trigger_id && v.bind
    ])
  }
}

resource "auth0_trigger_actions" "this" {
  for_each = local.triggers_with_actions
  trigger  = each.key

  dynamic "actions" {
    for_each = each.value
    content {
      id           = auth0_action.this[actions.value].id
      display_name = var.actions[actions.value].name
    }
  }
}
