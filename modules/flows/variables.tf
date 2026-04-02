variable "flows" {
  description = "Map of Auth0 Flows keyed by logical name. actions_json should have all tokens pre-replaced."
  type = map(object({
    name         = string
    actions_json = string
  }))
  default = {}
}
