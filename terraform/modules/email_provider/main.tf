# https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/email_provider
#
# Singleton resource — max 1 email provider per tenant.
# Supported providers: ses, sendgrid, smtp, azure_cs, ms365, mandrill, sparkpost, mailgun, custom.
#
# Required: name, default_from_address, credentials.
# credentials_static: non-secret values (e.g., smtp_host, region)
# credentials_secrets: map of credential field → pipeline secret name
# Env-specific values (e.g., default_from_address) go in env YAML.

locals {
  def = var.definition
  cfg = var.env_config

  # Merge static credentials + env-specific + pipeline secrets.
  credentials = merge(
    lookup(local.def, "credentials_static", {}),
    {
      for sk, secret_name in lookup(local.def, "credentials_secrets", {}) :
      sk => var.secrets[secret_name]
    },
    lookup(local.cfg, "credentials", {})
  )
}

resource "auth0_email_provider" "this" {
  name                 = local.def.name
  enabled              = lookup(local.def, "enabled", true)
  default_from_address = lookup(local.cfg, "default_from_address", local.def.default_from_address)

  credentials {
    # SES
    access_key_id     = lookup(local.credentials, "access_key_id", null)
    secret_access_key = lookup(local.credentials, "secret_access_key", null)
    region            = lookup(local.credentials, "region", null)

    # Sendgrid / Mandrill / SparkPost / Mailgun
    api_key = lookup(local.credentials, "api_key", null)
    domain  = lookup(local.credentials, "domain", null)

    # SMTP
    smtp_host = lookup(local.credentials, "smtp_host", null)
    smtp_port = lookup(local.credentials, "smtp_port", null)
    smtp_user = lookup(local.credentials, "smtp_user", null)
    smtp_pass = lookup(local.credentials, "smtp_pass", null)

    # Azure CS
    azure_cs_connection_string = lookup(local.credentials, "azure_cs_connection_string", null)

    # MS365
    ms365_tenant_id     = lookup(local.credentials, "ms365_tenant_id", null)
    ms365_client_id     = lookup(local.credentials, "ms365_client_id", null)
    ms365_client_secret = lookup(local.credentials, "ms365_client_secret", null)
  }

  dynamic "settings" {
    for_each = lookup(local.def, "settings", null) != null ? [local.def.settings] : []
    content {
      dynamic "message" {
        for_each = lookup(settings.value, "message", null) != null ? [settings.value.message] : []
        content {
          view_content_link      = lookup(message.value, "view_content_link", null)
          configuration_set_name = lookup(message.value, "configuration_set_name", null)
        }
      }

      dynamic "headers" {
        for_each = lookup(settings.value, "headers", null) != null ? [settings.value.headers] : []
        content {
          x_mc_view_content_link  = lookup(headers.value, "x_mc_view_content_link", null)
          x_ses_configuration_set = lookup(headers.value, "x_ses_configuration_set", null)
        }
      }
    }
  }
}
