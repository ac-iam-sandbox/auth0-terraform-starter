# ========================================
# Auth0 Log Stream Module
# Configures a log stream to AWS EventBridge with optional PII masking
# ========================================

resource "auth0_log_stream" "eventbridge" {
  name        = var.log_stream_name
  type        = "eventbridge"
  status      = var.status
  is_priority = var.is_priority

  # Filters - Auth0 accepts empty list, no need for conditional
  filters = var.filters

  sink {
    aws_account_id = var.aws_account_id
    aws_region     = var.aws_region
  }

  # PII Configuration - only when enabled AND fields are specified
  dynamic "pii_config" {
    for_each = var.enable_pii_masking && length(var.pii_log_fields) > 0 ? [1] : []

    content {
      log_fields = var.pii_log_fields
      method     = var.pii_method
      algorithm  = var.pii_algorithm
    }
  }
}