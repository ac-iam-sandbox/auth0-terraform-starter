# =============================================================================
# Auth0 Journeys (Vault Connections + Flows + Forms)
# =============================================================================
# Replaces token placeholders with real Terraform-managed IDs inside a single
# module so forms reference actual Auth0 flow IDs and flows reference actual
# vault connection IDs.
# =============================================================================

resource "auth0_flow_vault_connection" "this" {
  for_each = var.vault_connections

  name         = each.value.name
  app_id       = each.value.app_id
  account_name = try(each.value.account_name, null)
  environment  = try(each.value.environment, null)
  setup        = each.value.setup

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  vault_ids = { for k, v in auth0_flow_vault_connection.this : k => v.id }

  flow_actions_json = {
    for k, v in var.flows : k => replace(
      replace(
        replace(
          replace(
            replace(
              v.actions_json,
              try(keys(try(v.token_replacements, {}))[0], "__noop_0__"),
              try(local.vault_ids[values(try(v.token_replacements, {}))[0]], "")
            ),
            try(keys(try(v.token_replacements, {}))[1], "__noop_1__"),
            try(local.vault_ids[values(try(v.token_replacements, {}))[1]], "")
          ),
          try(keys(try(v.token_replacements, {}))[2], "__noop_2__"),
          try(local.vault_ids[values(try(v.token_replacements, {}))[2]], "")
        ),
        try(keys(try(v.token_replacements, {}))[3], "__noop_3__"),
        try(local.vault_ids[values(try(v.token_replacements, {}))[3]], "")
      ),
      try(keys(try(v.token_replacements, {}))[4], "__noop_4__"),
      try(local.vault_ids[values(try(v.token_replacements, {}))[4]], "")
    )
  }
}

resource "auth0_flow" "this" {
  for_each = var.flows

  name    = each.value.name
  actions = local.flow_actions_json[each.key]

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  flow_ids = { for k, v in auth0_flow.this : k => v.id }

  form_start_json = {
    for k, v in var.forms : k => replace(
      replace(
        replace(
          replace(
            replace(
              v.start_json,
              try(keys(try(v.token_replacements, {}))[0], "__noop_0__"),
              try(local.flow_ids[values(try(v.token_replacements, {}))[0]], "")
            ),
            try(keys(try(v.token_replacements, {}))[1], "__noop_1__"),
            try(local.flow_ids[values(try(v.token_replacements, {}))[1]], "")
          ),
          try(keys(try(v.token_replacements, {}))[2], "__noop_2__"),
          try(local.flow_ids[values(try(v.token_replacements, {}))[2]], "")
        ),
        try(keys(try(v.token_replacements, {}))[3], "__noop_3__"),
        try(local.flow_ids[values(try(v.token_replacements, {}))[3]], "")
      ),
      try(keys(try(v.token_replacements, {}))[4], "__noop_4__"),
      try(local.flow_ids[values(try(v.token_replacements, {}))[4]], "")
    )
  }

  form_nodes_json = {
    for k, v in var.forms : k => replace(
      replace(
        replace(
          replace(
            replace(
              v.nodes_json,
              try(keys(try(v.token_replacements, {}))[0], "__noop_0__"),
              try(local.flow_ids[values(try(v.token_replacements, {}))[0]], "")
            ),
            try(keys(try(v.token_replacements, {}))[1], "__noop_1__"),
            try(local.flow_ids[values(try(v.token_replacements, {}))[1]], "")
          ),
          try(keys(try(v.token_replacements, {}))[2], "__noop_2__"),
          try(local.flow_ids[values(try(v.token_replacements, {}))[2]], "")
        ),
        try(keys(try(v.token_replacements, {}))[3], "__noop_3__"),
        try(local.flow_ids[values(try(v.token_replacements, {}))[3]], "")
      ),
      try(keys(try(v.token_replacements, {}))[4], "__noop_4__"),
      try(local.flow_ids[values(try(v.token_replacements, {}))[4]], "")
    )
  }
}

resource "auth0_form" "this" {
  for_each = var.forms

  name = each.value.name

  start        = local.form_start_json[each.key]
  nodes        = local.form_nodes_json[each.key]
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
