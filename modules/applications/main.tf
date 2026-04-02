# =============================================================================
# Auth0 applications - data-driven via for_each
# =============================================================================
# Creates auth0_client + auth0_client_credentials for every entry in
# var.applications. Smart defaults per app_type eliminate boilerplate.
#
# SAFETY: prevent_destroy is enabled on all clients to prevent
# accidental deletion via Terraform. To remove a client, first
# remove prevent_destroy, plan, review carefully, then apply.
# =============================================================================

locals {
  # Grant type defaults per application type
  grant_type_defaults = {
    spa             = ["authorization_code", "implicit", "refresh_token"]
    regular_web     = ["authorization_code", "client_credentials", "refresh_token"]
    non_interactive = ["client_credentials"]
    native          = ["authorization_code", "refresh_token"]
  }

  # Authentication method defaults per application type
  auth_method_defaults = {
    spa             = "none"
    regular_web     = "client_secret_post"
    non_interactive = "client_secret_post"
    native          = "none"
  }

  # Refresh token defaults - only for app types that support it
  refresh_token_defaults = {
    spa = {
      rotation_type   = "rotating"
      expiration_type = "expiring"
      token_lifetime  = 2592000
      idle_token_lifetime = 1296000
    }
    regular_web = {
      rotation_type   = "rotating"
      expiration_type = "expiring"
      token_lifetime  = 2592000
      idle_token_lifetime = 1296000
    }
    native = {
      rotation_type   = "rotating"
      expiration_type = "expiring"
      token_lifetime  = 2592000
      idle_token_lifetime = 1296000
    }
  }
}

resource "auth0_client" "this" {
  for_each = var.applications

  name            = each.value.name
  description     = each.value.description
  app_type        = each.value.app_type
  is_first_party  = each.value.is_first_party
  oidc_conformant = true

  callbacks           = each.value.callbacks
  allowed_logout_urls = each.value.allowed_logout_urls
  web_origins         = each.value.web_origins
  allowed_origins     = each.value.allowed_origins
  logo_uri            = each.value.logo_uri
  initiate_login_uri  = each.value.initiate_login_uri
  client_metadata     = each.value.client_metadata

  grant_types = coalesce(
    each.value.grant_types,
    local.grant_type_defaults[each.value.app_type]
  )

  organization_usage            = each.value.organization_usage
  organization_require_behavior = each.value.organization_require_behavior

  jwt_configuration {
    alg                 = "RS256"
    lifetime_in_seconds = coalesce(each.value.jwt_lifetime_seconds, 36000)
  }

  # Refresh token - use explicit config, or smart defaults, or skip for M2M
  dynamic "refresh_token" {
    for_each = (
      each.value.refresh_token != null
      ? [each.value.refresh_token]
      : (
        contains(keys(local.refresh_token_defaults), each.value.app_type)
        ? [local.refresh_token_defaults[each.value.app_type]]
        : []
      )
    )
    content {
      rotation_type   = refresh_token.value.rotation_type
      expiration_type = refresh_token.value.expiration_type
      token_lifetime  = refresh_token.value.token_lifetime
      idle_token_lifetime = refresh_token.value.idle_token_lifetime
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Every client needs credentials
resource "auth0_client_credentials" "this" {
  for_each = var.applications

  client_id             = auth0_client.this[each.key].id
  authentication_method = coalesce(
    each.value.authentication_method,
    local.auth_method_defaults[each.value.app_type]
  )
}
