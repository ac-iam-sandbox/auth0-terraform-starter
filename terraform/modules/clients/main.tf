# https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/client

resource "auth0_client" "this" {
  for_each = var.definitions

  name            = each.value.name
  description     = lookup(each.value, "description", null)
  app_type        = each.value.app_type
  oidc_conformant = lookup(each.value, "oidc_conformant", true)
  is_first_party  = lookup(each.value, "is_first_party", true)

  # Resolve env-specific values from env_config using the _key fields.
  # M2M clients without callbacks_key get empty lists.
  callbacks           = lookup(each.value, "callbacks_key", null) != null ? var.env_config[each.value.callbacks_key] : []
  allowed_logout_urls = lookup(each.value, "logout_urls_key", null) != null ? var.env_config[each.value.logout_urls_key] : []
  web_origins         = lookup(each.value, "web_origins_key", null) != null ? var.env_config[each.value.web_origins_key] : null

  grant_types = lookup(each.value, "grant_types", [])

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
