# Log streams

locals {
  active = {
    for k, v in var.definitions : k => v
    if contains(v.environments, var.environment)
  }
}

resource "auth0_log_stream" "this" {
  for_each = local.active

  name        = each.value.name
  type        = each.value.type
  status      = lookup(each.value, "status", "active")
  is_priority = lookup(each.value, "is_priority", null)
  start_from  = lookup(each.value, "start_from", null)

  # Filters: List of maps with "type" and "name" keys.
  # Example: [{type = "category", name = "auth.login.fail"}]
  filters = lookup(each.value, "filters", null)

  sink {
    # HTTP
    http_endpoint       = lookup(local.resolved_sink[each.key], "http_endpoint", null)
    http_content_type   = lookup(local.resolved_sink[each.key], "http_content_type", null)
    http_content_format = lookup(local.resolved_sink[each.key], "http_content_format", null)
    http_authorization  = lookup(local.resolved_sink[each.key], "http_authorization", null)
    http_custom_headers = lookup(local.resolved_sink[each.key], "http_custom_headers", null)

    # EventBridge
    aws_account_id = lookup(local.resolved_sink[each.key], "aws_account_id", null)
    aws_region     = lookup(local.resolved_sink[each.key], "aws_region", null)

    # Azure Event Grid
    azure_subscription_id = lookup(local.resolved_sink[each.key], "azure_subscription_id", null)
    azure_resource_group  = lookup(local.resolved_sink[each.key], "azure_resource_group", null)
    azure_region          = lookup(local.resolved_sink[each.key], "azure_region", null)

    # Datadog
    datadog_region  = lookup(local.resolved_sink[each.key], "datadog_region", null)
    datadog_api_key = lookup(local.resolved_sink[each.key], "datadog_api_key", null)

    # Splunk
    splunk_domain = lookup(local.resolved_sink[each.key], "splunk_domain", null)
    splunk_token  = lookup(local.resolved_sink[each.key], "splunk_token", null)
    splunk_port   = lookup(local.resolved_sink[each.key], "splunk_port", null)
    splunk_secure = lookup(local.resolved_sink[each.key], "splunk_secure", null)

    # Sumo Logic
    sumo_source_address = lookup(local.resolved_sink[each.key], "sumo_source_address", null)

    # Mixpanel
    mixpanel_region                   = lookup(local.resolved_sink[each.key], "mixpanel_region", null)
    mixpanel_project_id               = lookup(local.resolved_sink[each.key], "mixpanel_project_id", null)
    mixpanel_service_account_username = lookup(local.resolved_sink[each.key], "mixpanel_service_account_username", null)
    mixpanel_service_account_password = lookup(local.resolved_sink[each.key], "mixpanel_service_account_password", null)

    # Segment
    segment_write_key = lookup(local.resolved_sink[each.key], "segment_write_key", null)
  }

  dynamic "pii_config" {
    for_each = lookup(each.value, "pii_config", null) != null ? [each.value.pii_config] : []
    content {
      log_fields = pii_config.value.log_fields
      algorithm  = lookup(pii_config.value, "algorithm", null)
      method     = lookup(pii_config.value, "method", null)
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  # Merge sink config: static manifest values + env-specific overrides + pipeline secrets.
  resolved_sink = {
    for k, v in local.active : k => merge(
      lookup(v, "sink_static", {}),
      lookup(lookup(var.env_config, k, {}), "sink", {}),
      {
        for sk, secret_name in lookup(v, "sink_secrets", {}) :
        sk => var.secrets[secret_name]
      }
    )
  }
}
