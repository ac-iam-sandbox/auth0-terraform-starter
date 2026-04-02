variable "vault_connections" {
  description = "Map of Auth0 Flow vault connections keyed by logical name"
  type = map(object({
    name         = string
    app_id       = string # AUTH0, TWILIO, SENDGRID, HTTP, etc.
    account_name = optional(string, null)
    environment  = optional(string, null)
    setup        = optional(map(string), {})
  }))
  default = {}
}
