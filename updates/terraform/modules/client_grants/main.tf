# Client grants
locals {
  active = {
    for k, v in var.definitions : k => v
    if(
      contains(v.environments, var.environment) &&
      (lookup(v, "regions", null) == null || contains(v.regions, var.region))
    )
  }

  resolved_audience = {
    for k, v in local.active : k =>
    lookup(v, "audience", null) == null || lookup(v, "audience", "") == "management_api"
    ? var.management_api_identifier
    : v.audience
  }
}

resource "auth0_client_grant" "this" {
  for_each = local.active

  client_id = var.client_ids[each.value.client_key]
  audience  = local.resolved_audience[each.key]

  scopes           = lookup(each.value, "allow_all_scopes", false) ? null : lookup(each.value, "scopes", [])
  allow_all_scopes = lookup(each.value, "allow_all_scopes", null)
  subject_type     = lookup(each.value, "subject_type", null)

  organization_usage     = lookup(each.value, "organization_usage", null)
  allow_any_organization = lookup(each.value, "allow_any_organization", null)

  authorization_details_types = lookup(each.value, "authorization_details_types", null)

  lifecycle {
    prevent_destroy = true
  }
}
