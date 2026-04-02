# =============================================================================
# Auth0 Action Modules - data-driven via for_each
# =============================================================================
# Action Modules are reusable code packages shared across multiple actions.
# Write common functionality once, use it in any action.
#
# SAFETY: prevent_destroy to avoid accidental deletion.
# =============================================================================

resource "auth0_action_module" "this" {
  for_each = var.action_modules

  name    = each.value.name
  code    = each.value.code
  publish = each.value.publish

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
