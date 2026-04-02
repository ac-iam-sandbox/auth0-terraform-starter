# =============================================================================
# Auth0 Flow Vault Connections - data-driven via for_each
# =============================================================================

resource "auth0_flow_vault_connection" "this" {
  for_each = var.vault_connections

  name         = each.value.name
  app_id       = each.value.app_id
  account_name = try(each.value.account_name, null)
  environment  = try(each.value.environment, null)

  setup = each.value.setup

  lifecycle {
    prevent_destroy = true
  }
}
