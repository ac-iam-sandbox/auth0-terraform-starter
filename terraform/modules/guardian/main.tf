# Guardian 

locals {
  def = var.definition
  cfg = var.env_config
}

resource "auth0_guardian" "this" {
  policy        = lookup(local.cfg, "policy", local.def.policy)
  email         = lookup(local.def, "email", false)
  otp           = lookup(local.def, "otp", false)
  recovery_code = lookup(local.def, "recovery_code", false)

  dynamic "phone" {
    for_each = lookup(local.def, "phone", null) != null ? [local.def.phone] : []
    content {
      enabled       = phone.value.enabled
      provider      = lookup(phone.value, "provider", "auth0")
      message_types = lookup(phone.value, "message_types", ["sms"])

      dynamic "options" {
        for_each = lookup(phone.value, "options", null) != null ? [phone.value.options] : []
        content {
          enrollment_message    = lookup(options.value, "enrollment_message", null)
          verification_message  = lookup(options.value, "verification_message", null)
          from                  = lookup(options.value, "from", null)
          messaging_service_sid = lookup(options.value, "messaging_service_sid", null)
          auth_token            = lookup(options.value, "auth_token", null)
          sid                   = lookup(options.value, "sid", null)
        }
      }
    }
  }

  dynamic "webauthn_roaming" {
    for_each = lookup(local.def, "webauthn_roaming", null) != null ? [local.def.webauthn_roaming] : []
    content {
      enabled                  = webauthn_roaming.value.enabled
      user_verification        = lookup(webauthn_roaming.value, "user_verification", "discouraged")
      override_relying_party   = lookup(webauthn_roaming.value, "override_relying_party", null)
      relying_party_identifier = lookup(webauthn_roaming.value, "relying_party_identifier", null)
    }
  }

  dynamic "webauthn_platform" {
    for_each = lookup(local.def, "webauthn_platform", null) != null ? [local.def.webauthn_platform] : []
    content {
      enabled                  = webauthn_platform.value.enabled
      override_relying_party   = lookup(webauthn_platform.value, "override_relying_party", null)
      relying_party_identifier = lookup(webauthn_platform.value, "relying_party_identifier", null)
    }
  }

  dynamic "duo" {
    for_each = lookup(local.def, "duo", null) != null ? [local.def.duo] : []
    content {
      enabled         = duo.value.enabled
      integration_key = lookup(duo.value, "integration_key", null)
      secret_key      = lookup(duo.value, "secret_key", null)
      hostname        = lookup(duo.value, "hostname", null)
    }
  }

  dynamic "push" {
    for_each = lookup(local.def, "push", null) != null ? [local.def.push] : []
    content {
      enabled  = push.value.enabled
      provider = lookup(push.value, "provider", "guardian")

      dynamic "amazon_sns" {
        for_each = lookup(push.value, "amazon_sns", null) != null ? [push.value.amazon_sns] : []
        content {
          aws_access_key_id                 = amazon_sns.value.aws_access_key_id
          aws_secret_access_key             = amazon_sns.value.aws_secret_access_key
          aws_region                        = amazon_sns.value.aws_region
          sns_apns_platform_application_arn = amazon_sns.value.sns_apns_platform_application_arn
          sns_gcm_platform_application_arn  = amazon_sns.value.sns_gcm_platform_application_arn
        }
      }

      dynamic "custom_app" {
        for_each = lookup(push.value, "custom_app", null) != null ? [push.value.custom_app] : []
        content {
          app_name        = lookup(custom_app.value, "app_name", null)
          apple_app_link  = lookup(custom_app.value, "apple_app_link", null)
          google_app_link = lookup(custom_app.value, "google_app_link", null)
        }
      }

      dynamic "direct_apns" {
        for_each = lookup(push.value, "direct_apns", null) != null ? [push.value.direct_apns] : []
        content {
          sandbox   = direct_apns.value.sandbox
          bundle_id = direct_apns.value.bundle_id
          p12       = direct_apns.value.p12
          enabled   = lookup(direct_apns.value, "enabled", null)
        }
      }

      dynamic "direct_fcm" {
        for_each = lookup(push.value, "direct_fcm", null) != null ? [push.value.direct_fcm] : []
        content {
          server_key = direct_fcm.value.server_key
        }
      }
    }
  }
}
