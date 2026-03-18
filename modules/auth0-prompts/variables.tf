# ========================================
# Auth0 Prompts Module - Input Variables
# ========================================

variable "universal_login_experience" {
  type        = string
  description = "Universal Login experience version (new or classic)"
  default     = "new"

  validation {
    condition     = contains(["new", "classic"], var.universal_login_experience)
    error_message = "Must be either 'new' or 'classic'"
  }
}

variable "identifier_first" {
  type        = bool
  description = "Whether to use identifier-first authentication flow"
  default     = true
}

variable "webauthn_platform_first_factor" {
  type        = bool
  description = "Whether to use WebAuthn as the first authentication factor"
  default     = false
}

variable "prompt_type" {
  type        = string
  description = "The prompt to add partials for"

  validation {
    condition = contains([
      "login-id", "login", "login-password", "signup",
      "signup-id", "signup-password", "login-passwordless",
      "customized-consent"
    ], var.prompt_type)
    error_message = "Invalid prompt type for screen partials"
  }
}