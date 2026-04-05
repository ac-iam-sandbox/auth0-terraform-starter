locals {
  # Filter clients by environments list.
  active_clients = {
    for k, v in var.definitions : k => v
    if lookup(v, "environments", null) == null || contains(v.environments, var.environment)
  }
}

resource "auth0_client" "this" {
  for_each = local.active_clients

  name            = each.value.name
  description     = lookup(each.value, "description", null)
  app_type        = each.value.app_type
  oidc_conformant = lookup(each.value, "oidc_conformant", true)
  is_first_party  = lookup(each.value, "is_first_party", true)

  # ── Env-specific URL properties (from environments/{env}.yaml → clients.{key}) ──
  callbacks           = try(var.env_config[each.key].callbacks, [])
  allowed_logout_urls = try(var.env_config[each.key].logout_urls, [])
  web_origins         = try(var.env_config[each.key].web_origins, null)
  allowed_origins     = try(var.env_config[each.key].allowed_origins, null)
  initiate_login_uri  = try(var.env_config[each.key].initiate_login_uri, null)

  # ── Static properties (from clients.yaml — same across all envs) ──
  grant_types          = lookup(each.value, "grant_types", [])
  logo_uri             = lookup(each.value, "logo_uri", null)
  cross_origin_auth    = lookup(each.value, "cross_origin_auth", null)
  custom_login_page_on = lookup(each.value, "custom_login_page_on", null)

  jwt_configuration {
    alg = lookup(each.value, "jwt_alg", "RS256")
  }

  dynamic "refresh_token" {
    for_each = lookup(each.value, "refresh_token", null) != null ? [each.value.refresh_token] : []
    content {
      rotation_type       = refresh_token.value.rotation_type
      expiration_type     = refresh_token.value.expiration_type
      token_lifetime      = lookup(refresh_token.value, "token_lifetime", null)
      idle_token_lifetime = lookup(refresh_token.value, "idle_token_lifetime", null)
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}
