variable "forms" {
  description = "Map of Auth0 Forms keyed by logical name"
  type = map(object({
    name              = string
    start_json        = string # JSON-encoded start config (with tokens replaced)
    nodes_json        = string # JSON-encoded nodes array (with tokens replaced)
    ending_json       = string # JSON-encoded ending config
    style_json        = optional(string, null)
    translations_json = optional(string, null)
    language_primary  = optional(string, "en")
    language_default  = optional(string, "en")
  }))
  default = {}
}

variable "environment" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
