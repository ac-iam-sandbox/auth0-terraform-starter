# https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/flow_vault_connection
#
# Creates auth0_flow_vault_connection resources.
#
# The setup map is built from three sources:
#   1. Static values (type) — directly from manifest
#   2. Env-specific values (domain, client_id) — resolved per environment
#   3. Secret values (client_secret) — from var.secrets via pipeline

locals {
  resolved = {
    for k, v in var.definitions : k => merge(
      # Static non-env values
      {
        for sk, sv in lookup(v, "setup", {}) :
        sk => sv if !can(sv["dev"])  # not an env-keyed map
      },
      # Env-specific values
      {
        for sk, sv in lookup(v, "setup", {}) :
        sk => lookup(sv, var.environment, lookup(sv, "default", ""))
        if can(sv["dev"])  # is an env-keyed map
      },
      # Secret values
      {
        for sk, secret_name in lookup(v, "setup_secrets", {}) :
        sk => var.secrets[secret_name]
      }
    )
  }
}

resource "auth0_flow_vault_connection" "this" {
  for_each = var.definitions

  app_id = each.value.app_id
  name   = each.value.name
  setup  = local.resolved[each.key]

  lifecycle {
    prevent_destroy = true
  }
}
