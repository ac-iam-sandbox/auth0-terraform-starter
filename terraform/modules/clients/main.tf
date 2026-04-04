# https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/client
#
# env_config is the "clients" section from environments/{env}.yaml.
# Each key matches a client key in clients.yaml.
# If a client has an "environments" list and the current env isn't in it, skip it.

locals {
  # Filter clients by environments list. No list = all environments.
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

  # Env-specific values from environments/{env}.yaml → clients.{key}
  # M2M clients without env config get empty lists.
  callbacks           = try(var.env_config[each.key].callbacks, [])
  allowed_logout_urls = try(var.env_config[each.key].logout_urls, [])
  web_origins         = try(var.env_config[each.key].web_origins, null)

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
