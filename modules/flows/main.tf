# =============================================================================
# Auth0 Flows - data-driven via for_each
# =============================================================================
# Token replacement (#CONN-1# → vault connection name) is performed at the
# Terragrunt stack level before data reaches this module. By the time
# actions_json arrives here, all tokens are already resolved.
# =============================================================================

resource "auth0_flow" "this" {
  for_each = var.flows

  name    = each.value.name
  actions = each.value.actions_json

  lifecycle {
    prevent_destroy = true
  }
}
