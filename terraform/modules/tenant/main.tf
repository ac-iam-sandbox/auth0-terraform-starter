# https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/tenant
#
# Singleton resource — manages existing tenant created through dashboard.
# Env-specific values (friendly_name, support_email, etc.) from env YAML.

locals {
  def = var.definition
  cfg = var.env_config
}

resource "auth0_tenant" "this" {
  # ── Basic settings ──
  friendly_name           = lookup(local.cfg, "friendly_name", lookup(local.def, "friendly_name", null))
  picture_url             = lookup(local.cfg, "picture_url", lookup(local.def, "picture_url", null))
  support_email           = lookup(local.cfg, "support_email", lookup(local.def, "support_email", null))
  support_url             = lookup(local.cfg, "support_url", lookup(local.def, "support_url", null))
  default_audience        = lookup(local.cfg, "default_audience", lookup(local.def, "default_audience", null))
  default_directory       = lookup(local.cfg, "default_directory", lookup(local.def, "default_directory", null))
  default_redirection_uri = lookup(local.cfg, "default_redirection_uri", lookup(local.def, "default_redirection_uri", null))
  allowed_logout_urls     = lookup(local.cfg, "allowed_logout_urls", lookup(local.def, "allowed_logout_urls", null))
  enabled_locales         = lookup(local.def, "enabled_locales", null)
  sandbox_version         = lookup(local.def, "sandbox_version", null)

  # ── Session settings ──
  idle_session_lifetime            = lookup(local.def, "idle_session_lifetime", null)
  session_lifetime                 = lookup(local.def, "session_lifetime", null)
  ephemeral_session_lifetime       = lookup(local.def, "ephemeral_session_lifetime", null)
  idle_ephemeral_session_lifetime  = lookup(local.def, "idle_ephemeral_session_lifetime", null)

  # ── Feature toggles ──
  customize_mfa_in_postlogin_action                    = lookup(local.def, "customize_mfa_in_postlogin_action", null)
  allow_organization_name_in_authentication_api        = lookup(local.def, "allow_organization_name_in_authentication_api", null)
  pushed_authorization_requests_supported              = lookup(local.def, "pushed_authorization_requests_supported", null)
  disable_acr_values_supported                         = lookup(local.def, "disable_acr_values_supported", null)
  phone_consolidated_experience                        = lookup(local.def, "phone_consolidated_experience", null)

  dynamic "session_cookie" {
    for_each = lookup(local.def, "session_cookie", null) != null ? [local.def.session_cookie] : []
    content {
      mode = session_cookie.value.mode
    }
  }

  dynamic "sessions" {
    for_each = lookup(local.def, "sessions", null) != null ? [local.def.sessions] : []
    content {
      oidc_logout_prompt_enabled = sessions.value.oidc_logout_prompt_enabled
    }
  }

  # ── mTLS ──
  dynamic "mtls" {
    for_each = lookup(local.def, "mtls", null) != null ? [local.def.mtls] : []
    content {
      disable                = lookup(mtls.value, "disable", null)
      enable_endpoint_aliases = lookup(mtls.value, "enable_endpoint_aliases", null)
    }
  }

  # ── OIDC logout ──
  dynamic "oidc_logout" {
    for_each = lookup(local.def, "oidc_logout", null) != null ? [local.def.oidc_logout] : []
    content {
      rp_logout_end_session_endpoint_discovery = oidc_logout.value.rp_logout_end_session_endpoint_discovery
    }
  }

  # ── Default token quota ──
  dynamic "default_token_quota" {
    for_each = lookup(local.def, "default_token_quota", null) != null ? [local.def.default_token_quota] : []
    content {
      dynamic "clients" {
        for_each = lookup(default_token_quota.value, "clients", null) != null ? [default_token_quota.value.clients] : []
        content {
          client_credentials {
            per_hour = lookup(clients.value.client_credentials, "per_hour", null)
            per_day  = lookup(clients.value.client_credentials, "per_day", null)
            enforce  = lookup(clients.value.client_credentials, "enforce", null)
          }
        }
      }

      dynamic "organizations" {
        for_each = lookup(default_token_quota.value, "organizations", null) != null ? [default_token_quota.value.organizations] : []
        content {
          client_credentials {
            per_hour = lookup(organizations.value.client_credentials, "per_hour", null)
            per_day  = lookup(organizations.value.client_credentials, "per_day", null)
            enforce  = lookup(organizations.value.client_credentials, "enforce", null)
          }
        }
      }
    }
  }

  # ── Flags ──
  dynamic "flags" {
    for_each = lookup(local.def, "flags", null) != null ? [local.def.flags] : []
    content {
      enable_client_connections                    = lookup(flags.value, "enable_client_connections", null)
      enable_apis_section                          = lookup(flags.value, "enable_apis_section", null)
      enable_custom_domain_in_emails               = lookup(flags.value, "enable_custom_domain_in_emails", null)
      enable_dynamic_client_registration           = lookup(flags.value, "enable_dynamic_client_registration", null)
      enable_sso                                   = lookup(flags.value, "enable_sso", null)
      enable_pipeline2                             = lookup(flags.value, "enable_pipeline2", null)
      enable_public_signup_user_exists_error        = lookup(flags.value, "enable_public_signup_user_exists_error", null)
      no_disclose_enterprise_connections            = lookup(flags.value, "no_disclose_enterprise_connections", null)
      disable_management_api_sms_obfuscation        = lookup(flags.value, "disable_management_api_sms_obfuscation", null)
      disable_clickjack_protection_headers          = lookup(flags.value, "disable_clickjack_protection_headers", null)
      disable_fields_map_fix                        = lookup(flags.value, "disable_fields_map_fix", null)
      allow_legacy_delegation_grant_types           = lookup(flags.value, "allow_legacy_delegation_grant_types", null)
      allow_legacy_ro_grant_types                   = lookup(flags.value, "allow_legacy_ro_grant_types", null)
      allow_legacy_tokeninfo_endpoint               = lookup(flags.value, "allow_legacy_tokeninfo_endpoint", null)
      enable_legacy_profile                         = lookup(flags.value, "enable_legacy_profile", null)
      enable_idtoken_api2                           = lookup(flags.value, "enable_idtoken_api2", null)
      enable_legacy_logs_search_v2                  = lookup(flags.value, "enable_legacy_logs_search_v2", null)
      enable_adfs_waad_email_verification           = lookup(flags.value, "enable_adfs_waad_email_verification", null)
      revoke_refresh_token_grant                    = lookup(flags.value, "revoke_refresh_token_grant", null)
      dashboard_log_streams_next                    = lookup(flags.value, "dashboard_log_streams_next", null)
      dashboard_insights_view                       = lookup(flags.value, "dashboard_insights_view", null)
      mfa_show_factor_list_on_enrollment            = lookup(flags.value, "mfa_show_factor_list_on_enrollment", null)
      use_scope_descriptions_for_consent            = lookup(flags.value, "use_scope_descriptions_for_consent", null)
      remove_alg_from_jwks                          = lookup(flags.value, "remove_alg_from_jwks", null)
    }
  }

  # ── Error page ──
  dynamic "error_page" {
    for_each = lookup(local.def, "error_page", null) != null ? [local.def.error_page] : []
    content {
      html          = lookup(error_page.value, "html", null)
      show_log_link = lookup(error_page.value, "show_log_link", null)
      url           = lookup(local.cfg, "error_page_url", lookup(error_page.value, "url", null))
    }
  }
}
