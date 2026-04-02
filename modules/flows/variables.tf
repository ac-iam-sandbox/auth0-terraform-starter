variable "flows" {
  description = "Map of Auth0 Flows keyed by logical name"
  type = map(object({
    name         = string
    actions_json = string # JSON-encoded actions array (with tokens already replaced)
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
