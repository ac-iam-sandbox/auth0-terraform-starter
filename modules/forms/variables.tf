variable "forms" {
  description = "Map of Auth0 Forms keyed by logical name. JSON fields should have all tokens pre-replaced."
  type = map(object({
    name              = string
    start_json        = string
    nodes_json        = string
    ending_json       = string
    style_json        = optional(string, null)
    translations_json = optional(string, null)
    language_primary  = optional(string, "en")
    language_default  = optional(string, "en")
  }))
  default = {}
}
