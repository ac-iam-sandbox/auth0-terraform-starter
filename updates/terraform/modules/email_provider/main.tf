# Email provider
#
# When name="custom", an auth0_action with the custom-email-provider trigger
# is created as a prerequisite. The action's secrets are resolved from:
#   1. tenant_domain   — auto-injected as AUTH0_DOMAIN (no env YAML needed)
#   2. secrets_config  — per-env values from env YAML (e.g. AWS_REGION)
#   3. secrets_pipeline — map of action_secret_name → pipeline_var_name
#   4. client_refs      — auto-resolved client IDs/secrets from the clients module
#
# When name="ses" (or any other provider), the action is not created and
# credentials are resolved from credentials_static, credentials_secrets,
# and env YAML as before.

locals {
  def        = var.definition
  cfg        = var.env_config
  is_custom  = local.def.name == "custom"
  action_def = lookup(local.def, "action", {})

  # ── Credentials for non-custom providers (SES, SMTP, etc.) ──
  credentials = local.is_custom ? {} : merge(
    lookup(local.def, "credentials_static", {}),
    {
      for sk, secret_name in lookup(local.def, "credentials_secrets", {}) :
      sk => var.secrets[secret_name]
    },
    lookup(local.cfg, "credentials", {})
  )

  # ── Action secrets for custom provider ──
  action_env_config = lookup(local.cfg, "action", {})

  action_secrets = local.is_custom ? merge(
    # Auto-inject tenant domain — eliminates AUTH0_DOMAIN duplication in env YAMLs
    var.tenant_domain != "" ? { "AUTH0_DOMAIN" = var.tenant_domain } : {},
    # Per-env config values (e.g. AWS_REGION from env YAML)
    {
      for name in lookup(local.action_def, "secrets_config", []) :
      name => local.action_env_config[name]
    },
    # Pipeline secrets — map allows renaming (e.g. AWS_ACCESS_KEY_ID → SES_AWS_ACCESS_KEY_ID)
    {
      for secret_name, var_name in lookup(local.action_def, "secrets_pipeline", {}) :
      secret_name => var.secrets[var_name]
    },
    # Client refs — auto-resolved from clients module output
    {
      for ref in lookup(local.action_def, "client_refs", []) :
      ref.secret_name => (
        lookup(ref, "credential", null) == "secret"
        ? var.client_secrets[ref.client_key]
        : var.client_ids[ref.client_key]
      )
    }
  ) : {}
}

# ── Custom email provider action (only when name="custom") ──
resource "auth0_action" "email_provider" {
  count = local.is_custom ? 1 : 0

  name    = lookup(local.action_def, "name", "Custom Email Provider")
  runtime = lookup(local.action_def, "runtime", "node22")
  deploy  = true
  code    = file("${path.root}/email_provider_action/${lookup(local.action_def, "code", "main.js")}")

  supported_triggers {
    id      = "custom-email-provider"
    version = "v1"
  }

  dynamic "dependencies" {
    for_each = lookup(local.action_def, "dependencies", {})
    content {
      name    = dependencies.key
      version = dependencies.value
    }
  }

  dynamic "secrets" {
    for_each = local.action_secrets
    content {
      name  = secrets.key
      value = secrets.value
    }
  }

  # No prevent_destroy — if reverting from custom to SES,
  # count drops to 0 and this action must be destroyable.
}

# ── Email provider ──
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

  # When custom, the action must exist first.
  depends_on = [auth0_action.email_provider]
}
