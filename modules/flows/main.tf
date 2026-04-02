# =============================================================================
# Auth0 Flows - data-driven via for_each
# =============================================================================

resource "auth0_flow" "this" {
  for_each = var.flows

  name    = each.value.name
  actions = each.value.actions_json

  lifecycle {
    prevent_destroy = true
  }
}
