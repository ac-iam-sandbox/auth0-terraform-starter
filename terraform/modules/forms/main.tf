# https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/form
#
# Forms are created from exported dashboard JSON.
# Placeholder tokens are replaced with real Terraform-managed resource IDs.
#
# The forms definitions come from the "forms" key in flows.yaml,
# which specifies the replacement mappings for each form.

locals {
  # Filter to just the forms from the definitions
  form_defs = lookup(var.definitions, "forms", try(var.definitions, {}))

  # Resolve code file per form using testing block pattern
  # tflint-ignore: terraform_unused_declarations
  resolved_code = {
    for k, v in local.form_defs : k => (
      lookup(v, "testing", null) != null
      && contains(lookup(lookup(v, "testing", {}), "envs", []), var.environment)
    ) ? v.testing.file : v.code
  }
}

# TODO: Implement auth0_form resource creation.
# Each form needs its exported JSON loaded, then flow and connection
# placeholders replaced using the mappings in flow_replacements and
# connection_replacements. The auth0_form resource accepts:
#   name, start (json), nodes (json), ending (json), style (json)
#
# See: https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/form
