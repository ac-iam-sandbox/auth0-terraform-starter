# https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/client
#
# Creates auth0_client resources from YAML manifest definitions.
# M2M client grants are NOT managed here — a separate team handles
# permissions using the client_id output.

resource "auth0_client" "this" {
  for_each = var.definitions

  name            = each.value.name
  description     = lookup(each.value, "description", null)
  app_type        = each.value.app_type
  oidc_conformant = lookup(each.value, "oidc_conformant", true)
  is_first_party  = lookup(each.value, "is_first_party", true)

  callbacks = lookup(
    lookup(each.value, "callbacks", {}),
    var.environment,
    lookup(lookup(each.value, "callbacks", {}), "default", [])
  )

  allowed_logout_urls = lookup(
    lookup(each.value, "logout_urls", {}),
    var.environment,
    lookup(lookup(each.value, "logout_urls", {}), "default", [])
  )

  web_origins = lookup(
    lookup(each.value, "web_origins", {}),
    var.environment,
    lookup(lookup(each.value, "web_origins", {}), "default", null)
  )

  grant_types = lookup(each.value, "grant_types", [])

  jwt_configuration {
    alg = lookup(each.value, "jwt_alg", "RS256")
  }

  dynamic "refresh_token" {
    for_each = lookup(each.value, "refresh_token", null) != null ? [each.value.refresh_token] : []
    content {
      rotation_type           = refresh_token.value.rotation_type
      expiration_type         = refresh_token.value.expiration_type
      token_lifetime          = lookup(refresh_token.value, "token_lifetime", null)
      idle_token_lifetime     = lookup(refresh_token.value, "idle_token_lifetime", null)
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}
