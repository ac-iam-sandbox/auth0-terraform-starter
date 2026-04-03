variable "vault_connections" {
  description = "Map of Auth0 vault connections keyed by logical name."
  type = map(object({
    name         = string
    app_id       = string
    account_name = optional(string)
    environment  = optional(string)
    setup        = map(string)
  }))
  default = {}
}

variable "flows" {
  description = "Map of Auth0 flows keyed by logical name. Token replacements map placeholders to vault logical names."
  type = map(object({
    name               = string
    actions_json       = string
    token_replacements = optional(map(string), {})
  }))
  default = {}
}

variable "forms" {
  description = "Map of Auth0 forms keyed by logical name. Token replacements map placeholders to flow logical names."
  type = map(object({
    name               = string
    start_json         = string
    nodes_json         = string
    ending_json        = string
    style_json         = optional(string, null)
    translations_json  = optional(string, null)
    language_primary   = optional(string, "en")
    language_default   = optional(string, "en")
    token_replacements = optional(map(string), {})
  }))
  default = {}
}
