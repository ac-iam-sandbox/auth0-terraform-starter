# =============================================================================
# Auth0 Forms - data-driven via for_each
# =============================================================================
# Token replacement (#FLOW-1# → flow ID) is performed at the Terragrunt
# stack level before data reaches this module. By the time nodes_json and
# start_json arrive here, all tokens are already resolved.
# =============================================================================

resource "auth0_form" "this" {
  for_each = var.forms

  name = each.value.name

  start        = each.value.start_json
  nodes        = each.value.nodes_json
  ending       = each.value.ending_json
  style        = each.value.style_json
  translations = each.value.translations_json

  languages {
    primary = each.value.language_primary
    default = each.value.language_default
  }

  lifecycle {
    prevent_destroy = true
  }
}
