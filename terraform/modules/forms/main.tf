# https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/form
#
# Forms are created from exported dashboard JSON snapshots.
# Flow placeholders (#FLOW-N#) in nodes are replaced with Terraform-managed flow IDs.
# Translations, style, languages, and messages are extracted from the same export.
#
# val and prod environments MUST resolve to main.json. This is enforced by
# a lifecycle precondition that blocks plan if a testing override would apply.

locals {
  # Filter by environments list.
  active = {
    for k, v in var.definitions : k => v
    if lookup(v, "environments", null) == null || contains(v.environments, var.environment)
  }

  # Resolve export file: main.json or next.json via testing block.
  resolved_file = {
    for k, v in local.active : k => (
      lookup(v, "testing", null) != null
      && contains(lookup(lookup(v, "testing", {}), "envs", []), var.environment)
    ) ? v.testing.file : lookup(v, "code", "main.json")
  }

  # Whether testing override is active (for safety check).
  testing_active = {
    for k, v in local.active : k => (
      lookup(v, "testing", null) != null
      && contains(lookup(lookup(v, "testing", {}), "envs", []), var.environment)
    )
  }

  # Decoded export JSON per form.
  resolved_json = {
    for k, v in local.active : k =>
    jsondecode(file("${path.root}/manifests/forms/${k}/${local.resolved_file[k]}"))
  }

  # Extract the form section from each export.
  form_data = {
    for k in keys(local.active) : k => local.resolved_json[k]["form"]
  }

  # Build flow replacement map per form.
  flow_replacements = {
    for k, v in local.active : k => {
      for ref in lookup(v, "flow_refs", []) :
      ref.placeholder => var.flow_outputs[ref.flow_key]
    }
  }

  flow_keys = {
    for k, v in local.flow_replacements : k => keys(v)
  }

  # Chain-replace flow placeholders in nodes JSON.
  # Supports up to 6 flow refs per form (extend if needed).
  nodes_r0 = {
    for k in keys(local.active) : k => jsonencode(local.form_data[k]["nodes"])
  }
  nodes_r1 = {
    for k in keys(local.active) : k =>
    length(local.flow_keys[k]) >= 1
    ? replace(local.nodes_r0[k], local.flow_keys[k][0], local.flow_replacements[k][local.flow_keys[k][0]])
    : local.nodes_r0[k]
  }
  nodes_r2 = {
    for k in keys(local.active) : k =>
    length(local.flow_keys[k]) >= 2
    ? replace(local.nodes_r1[k], local.flow_keys[k][1], local.flow_replacements[k][local.flow_keys[k][1]])
    : local.nodes_r1[k]
  }
  nodes_r3 = {
    for k in keys(local.active) : k =>
    length(local.flow_keys[k]) >= 3
    ? replace(local.nodes_r2[k], local.flow_keys[k][2], local.flow_replacements[k][local.flow_keys[k][2]])
    : local.nodes_r2[k]
  }
  nodes_r4 = {
    for k in keys(local.active) : k =>
    length(local.flow_keys[k]) >= 4
    ? replace(local.nodes_r3[k], local.flow_keys[k][3], local.flow_replacements[k][local.flow_keys[k][3]])
    : local.nodes_r3[k]
  }
  nodes_r5 = {
    for k in keys(local.active) : k =>
    length(local.flow_keys[k]) >= 5
    ? replace(local.nodes_r4[k], local.flow_keys[k][4], local.flow_replacements[k][local.flow_keys[k][4]])
    : local.nodes_r4[k]
  }
  nodes_r6 = {
    for k in keys(local.active) : k =>
    length(local.flow_keys[k]) >= 6
    ? replace(local.nodes_r5[k], local.flow_keys[k][5], local.flow_replacements[k][local.flow_keys[k][5]])
    : local.nodes_r5[k]
  }

  nodes_final = local.nodes_r6
}

resource "auth0_form" "this" {
  for_each = local.active

  name = each.value.name

  start  = jsonencode(local.form_data[each.key]["start"])
  nodes  = local.nodes_final[each.key]
  ending = jsonencode(local.form_data[each.key]["ending"])
  style  = lookup(local.form_data[each.key], "style", null) != null ? jsonencode(local.form_data[each.key]["style"]) : null

  translations = lookup(local.form_data[each.key], "translations", null) != null ? jsonencode(local.form_data[each.key]["translations"]) : null

  languages {
    primary = local.form_data[each.key]["languages"]["primary"]
    default = lookup(local.form_data[each.key]["languages"], "default", local.form_data[each.key]["languages"]["primary"])
  }

  dynamic "messages" {
    for_each = lookup(local.form_data[each.key], "messages", null) != null ? [local.form_data[each.key]["messages"]] : []
    content {
      errors = lookup(messages.value, "errors", null) != null ? jsonencode(messages.value["errors"]) : null
      custom = lookup(messages.value, "custom", null) != null ? jsonencode(messages.value["custom"]) : null
    }
  }

  lifecycle {
    precondition {
      condition     = !(contains(["val", "prod"], var.environment) && local.testing_active[each.key])
      error_message = "Form '${each.key}': val and prod must not resolve testing artifacts. Promote by overwriting main.json and removing the testing block."
    }
    prevent_destroy = true
  }
}
