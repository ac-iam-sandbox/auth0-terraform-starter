# https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/flow
#
# Form-local flows: extracted from the owning form's exported JSON.
# Shared flows: read from their own source_file.
# Connection placeholders (#CONN-N#) are replaced with vault connection IDs.
# Chained replace() handles multiple placeholders per flow.

locals {
  # Filter by environments list.
  active = {
    for k, v in var.definitions : k => v
    if lookup(v, "environments", null) == null || contains(v.environments, var.environment)
  }

  # Resolve source file for form-local flows.
  # Form-local flows inherit the form's testing block resolution.
  # Shared flows resolve their own testing block.
  resolved_file = {
    for k, v in local.active : k => (
      # Form-local flow
      lookup(v, "source_form", null) != null ? (
        lookup(lookup(var.forms_manifest, v.source_form, {}), "testing", null) != null
        && contains(
          lookup(lookup(lookup(var.forms_manifest, v.source_form, {}), "testing", {}), "envs", []),
          var.environment
        )
        ? lookup(lookup(var.forms_manifest, v.source_form, {}), "testing", {}).file
        : lookup(lookup(var.forms_manifest, v.source_form, {}), "code", "main.json")
        ) : (
        # Shared flow
        lookup(v, "testing", null) != null
        && contains(lookup(lookup(v, "testing", {}), "envs", []), var.environment)
        ? v.testing.file
        : lookup(v, "source_file", "main.json")
      )
    )
  }

  # Whether testing override is active (for safety check).
  testing_active = {
    for k, v in local.active : k => (
      lookup(v, "source_form", null) != null ? (
        lookup(lookup(var.forms_manifest, v.source_form, {}), "testing", null) != null
        && contains(
          lookup(lookup(lookup(var.forms_manifest, v.source_form, {}), "testing", {}), "envs", []),
          var.environment
        )
        ) : (
        lookup(v, "testing", null) != null
        && contains(lookup(lookup(v, "testing", {}), "envs", []), var.environment)
      )
    )
  }

  # Read flow data from resolved files.
  resolved_flow_data = {
    for k, v in local.active : k =>
    lookup(v, "source_form", null) != null
    ? jsondecode(file("${path.root}/manifests/forms/${v.source_form}/${local.resolved_file[k]}"))["flows"][v.source_key]
    : (
      lookup(v, "source_file", null) != null
      ? jsondecode(file("${path.root}/${v.source_file}"))
      : null
    )
  }

  # Build connection replacement map per flow.
  conn_replacements = {
    for k, v in local.active : k => {
      for ref in lookup(v, "conn_refs", []) :
      ref.placeholder => var.vault_connection_outputs[ref.vault_key]
    }
  }

  conn_keys = {
    for k, v in local.conn_replacements : k => keys(v)
  }

  # Chain-replace connection placeholders in flow actions JSON.
  # Supports up to 6 conn refs per flow (extend if needed).
  actions_r0 = {
    for k in keys(local.active) : k =>
    local.resolved_flow_data[k] != null ? jsonencode(local.resolved_flow_data[k]["actions"]) : "[]"
  }
  actions_r1 = {
    for k in keys(local.active) : k =>
    length(local.conn_keys[k]) >= 1
    ? replace(local.actions_r0[k], local.conn_keys[k][0], local.conn_replacements[k][local.conn_keys[k][0]])
    : local.actions_r0[k]
  }
  actions_r2 = {
    for k in keys(local.active) : k =>
    length(local.conn_keys[k]) >= 2
    ? replace(local.actions_r1[k], local.conn_keys[k][1], local.conn_replacements[k][local.conn_keys[k][1]])
    : local.actions_r1[k]
  }
  actions_r3 = {
    for k in keys(local.active) : k =>
    length(local.conn_keys[k]) >= 3
    ? replace(local.actions_r2[k], local.conn_keys[k][2], local.conn_replacements[k][local.conn_keys[k][2]])
    : local.actions_r2[k]
  }
  actions_r4 = {
    for k in keys(local.active) : k =>
    length(local.conn_keys[k]) >= 4
    ? replace(local.actions_r3[k], local.conn_keys[k][3], local.conn_replacements[k][local.conn_keys[k][3]])
    : local.actions_r3[k]
  }

  actions_final = local.actions_r4
}

resource "auth0_flow" "this" {
  for_each = {
    for k, v in local.active : k => v
    if local.resolved_flow_data[k] != null
  }

  name    = each.value.name
  actions = local.actions_final[each.key]

  lifecycle {
    precondition {
      condition     = !(contains(["val", "prod"], var.environment) && local.testing_active[each.key])
      error_message = "Flow '${each.key}': val and prod must not resolve testing artifacts. Promote by overwriting main.json and removing the testing block."
    }
    prevent_destroy = true
  }
}
