variable "applications" {
  description = "Map of Auth0 applications keyed by stable logical name"
  type = map(object({
    name        = string
    app_type    = string # spa | regular_web | non_interactive | native
    description = optional(string, "")

    is_first_party = optional(bool, true)
    callbacks           = optional(list(string), [])
    allowed_logout_urls = optional(list(string), [])
    web_origins         = optional(list(string), [])
    allowed_origins     = optional(list(string), [])
    grant_types         = optional(list(string), null) # null = smart defaults per app_type
    logo_uri            = optional(string, null)
    initiate_login_uri  = optional(string, null)
    client_metadata     = optional(map(string), {})

    organization_usage            = optional(string, null)
    organization_require_behavior = optional(string, null)

    # Token settings
    jwt_lifetime_seconds  = optional(number, null) # default 36000 (10h)
    authentication_method = optional(string, null) # null = smart default per app_type

    # Refresh token (null = smart defaults for SPA/RWA/native, skip for M2M)
    refresh_token = optional(object({
      rotation_type       = optional(string, "rotating")
      expiration_type     = optional(string, "expiring")
      token_lifetime      = optional(number, 2592000)
      idle_token_lifetime = optional(number, 1296000)
    }), null)
  }))

  validation {
    condition = alltrue([
      for k, v in var.applications :
      contains(["spa", "regular_web", "non_interactive", "native"], v.app_type)
    ])
    error_message = "app_type must be one of: spa, regular_web, non_interactive, native."
  }
}

variable "environment" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
