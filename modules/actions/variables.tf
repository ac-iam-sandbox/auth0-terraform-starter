variable "actions" {
  description = "Map of Auth0 actions keyed by logical name"
  type = map(object({
    name            = string
    trigger_id      = string # post-login, credentials-exchange, etc.
    trigger_version = optional(string, "v3")
    runtime         = optional(string, "node22")
    deploy          = optional(bool, true)
    bind            = optional(bool, true)
    code            = string # JS source code (read from file)

    dependencies = optional(list(object({
      name    = string
      version = string
    })), [])

    secrets = optional(list(object({
      name  = string
      value = string
    })), [])
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
