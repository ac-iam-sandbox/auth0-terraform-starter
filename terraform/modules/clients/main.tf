# https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/client
#
# M2M-only clients. Filtered by both "environments" and optional "regions".
# Omitting "regions" means the client exists in all regions.

locals {
  active_clients = {
    for k, v in var.definitions : k => v
    if(
      contains(v.environments, var.environment) &&
      (lookup(v, "regions", null) == null || contains(v.regions, var.region))
    )
  }
}

resource "auth0_client" "this" {
  for_each = local.active_clients

  name             = each.value.name
  description      = lookup(each.value, "description", null)
  app_type         = "non_interactive"
  oidc_conformant  = lookup(each.value, "oidc_conformant", true)
  is_first_party   = lookup(each.value, "is_first_party", true)
  compliance_level = lookup(each.value, "compliance_level", null)

  grant_types = ["client_credentials"]

  client_metadata = lookup(each.value, "client_metadata", null)

  jwt_configuration {
    alg                 = lookup(each.value, "jwt_alg", "RS256")
    lifetime_in_seconds = lookup(each.value, "jwt_lifetime_in_seconds", null)
  }

  dynamic "token_quota" {
    for_each = lookup(each.value, "token_quota", null) != null ? [each.value.token_quota] : []
    content {
      client_credentials {
        per_hour = lookup(token_quota.value, "per_hour", null)
        per_day  = lookup(token_quota.value, "per_day", null)
        enforce  = lookup(token_quota.value, "enforce", null)
      }
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}
