# https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/flow
#
# Each flow's actions array is extracted from the exported form JSON.
# Vault connection placeholders (#CONN-N#) are replaced with real IDs.

resource "auth0_flow" "this" {
  for_each = var.definitions

  name = each.value.name

  # Load flow actions from exported form JSON, replace vault placeholders.
  # The source_form_flow_key identifies which flow within the exported JSON.
  actions = replace(
    jsonencode(
      jsondecode(
        file("${path.root}/manifests/forms/${each.value.source_form}/main.json")
      )["flows"][each.value.source_form_flow_key]["actions"]
    ),
    length(lookup(each.value, "vault_refs", [])) > 0 ? each.value.vault_refs[0].placeholder : "##NOOP##",
    length(lookup(each.value, "vault_refs", [])) > 0 ? var.vault_connection_outputs[each.value.vault_refs[0].key] : ""
  )
}
