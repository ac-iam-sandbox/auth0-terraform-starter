# =============================================================================
# Auth0 Forms - data-driven via for_each
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
