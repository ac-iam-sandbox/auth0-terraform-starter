# Attack protection

locals {
  def = var.definition
}

resource "auth0_attack_protection" "this" {

  dynamic "brute_force_protection" {
    for_each = lookup(local.def, "brute_force_protection", null) != null ? [local.def.brute_force_protection] : []
    content {
      enabled      = brute_force_protection.value.enabled
      shields      = lookup(brute_force_protection.value, "shields", [])
      allowlist    = lookup(brute_force_protection.value, "allowlist", [])
      mode         = lookup(brute_force_protection.value, "mode", "count_per_identifier_and_ip")
      max_attempts = lookup(brute_force_protection.value, "max_attempts", 10)
    }
  }

  dynamic "suspicious_ip_throttling" {
    for_each = lookup(local.def, "suspicious_ip_throttling", null) != null ? [local.def.suspicious_ip_throttling] : []
    content {
      enabled   = suspicious_ip_throttling.value.enabled
      shields   = lookup(suspicious_ip_throttling.value, "shields", [])
      allowlist = lookup(suspicious_ip_throttling.value, "allowlist", [])

      dynamic "pre_login" {
        for_each = lookup(suspicious_ip_throttling.value, "pre_login", null) != null ? [suspicious_ip_throttling.value.pre_login] : []
        content {
          max_attempts = lookup(pre_login.value, "max_attempts", null)
          rate         = lookup(pre_login.value, "rate", null)
        }
      }

      dynamic "pre_user_registration" {
        for_each = lookup(suspicious_ip_throttling.value, "pre_user_registration", null) != null ? [suspicious_ip_throttling.value.pre_user_registration] : []
        content {
          max_attempts = lookup(pre_user_registration.value, "max_attempts", null)
          rate         = lookup(pre_user_registration.value, "rate", null)
        }
      }
    }
  }

  dynamic "breached_password_detection" {
    for_each = lookup(local.def, "breached_password_detection", null) != null ? [local.def.breached_password_detection] : []
    content {
      enabled                      = breached_password_detection.value.enabled
      shields                      = lookup(breached_password_detection.value, "shields", [])
      admin_notification_frequency = lookup(breached_password_detection.value, "admin_notification_frequency", [])
      method                       = lookup(breached_password_detection.value, "method", "standard")

      dynamic "pre_user_registration" {
        for_each = lookup(breached_password_detection.value, "pre_user_registration", null) != null ? [breached_password_detection.value.pre_user_registration] : []
        content {
          shields = pre_user_registration.value.shields
        }
      }

      dynamic "pre_change_password" {
        for_each = lookup(breached_password_detection.value, "pre_change_password", null) != null ? [breached_password_detection.value.pre_change_password] : []
        content {
          shields = pre_change_password.value.shields
        }
      }
    }
  }

  dynamic "bot_detection" {
    for_each = lookup(local.def, "bot_detection", null) != null ? [local.def.bot_detection] : []
    content {
      bot_detection_level             = lookup(bot_detection.value, "bot_detection_level", null)
      challenge_password_policy       = lookup(bot_detection.value, "challenge_password_policy", null)
      challenge_passwordless_policy   = lookup(bot_detection.value, "challenge_passwordless_policy", null)
      challenge_password_reset_policy = lookup(bot_detection.value, "challenge_password_reset_policy", null)
      allowlist                       = lookup(bot_detection.value, "allowlist", [])
      monitoring_mode_enabled         = lookup(bot_detection.value, "monitoring_mode_enabled", null)
    }
  }

  dynamic "captcha" {
    for_each = lookup(local.def, "captcha", null) != null ? [local.def.captcha] : []
    content {
      active_provider_id = lookup(captcha.value, "active_provider_id", null)

      dynamic "recaptcha_v2" {
        for_each = lookup(captcha.value, "recaptcha_v2", null) != null ? [captcha.value.recaptcha_v2] : []
        content {
          site_key = recaptcha_v2.value.site_key
          secret   = lookup(recaptcha_v2.value, "secret", null)
        }
      }

      dynamic "recaptcha_enterprise" {
        for_each = lookup(captcha.value, "recaptcha_enterprise", null) != null ? [captcha.value.recaptcha_enterprise] : []
        content {
          site_key   = recaptcha_enterprise.value.site_key
          project_id = recaptcha_enterprise.value.project_id
          api_key    = lookup(recaptcha_enterprise.value, "api_key", null)
        }
      }

      dynamic "hcaptcha" {
        for_each = lookup(captcha.value, "hcaptcha", null) != null ? [captcha.value.hcaptcha] : []
        content {
          site_key = hcaptcha.value.site_key
          secret   = lookup(hcaptcha.value, "secret", null)
        }
      }

      dynamic "friendly_captcha" {
        for_each = lookup(captcha.value, "friendly_captcha", null) != null ? [captcha.value.friendly_captcha] : []
        content {
          site_key = friendly_captcha.value.site_key
          secret   = lookup(friendly_captcha.value, "secret", null)
        }
      }

      dynamic "arkose" {
        for_each = lookup(captcha.value, "arkose", null) != null ? [captcha.value.arkose] : []
        content {
          site_key         = arkose.value.site_key
          secret           = lookup(arkose.value, "secret", null)
          client_subdomain = lookup(arkose.value, "client_subdomain", null)
          verify_subdomain = lookup(arkose.value, "verify_subdomain", null)
          fail_open        = lookup(arkose.value, "fail_open", null)
        }
      }

      dynamic "auth_challenge" {
        for_each = lookup(captcha.value, "auth_challenge", null) != null ? [captcha.value.auth_challenge] : []
        content {
          fail_open = lookup(auth_challenge.value, "fail_open", null)
        }
      }
    }
  }
}
