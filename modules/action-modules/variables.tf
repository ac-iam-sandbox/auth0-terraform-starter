variable "action_modules" {
  description = "Map of Auth0 Action Modules keyed by logical name"
  type = map(object({
    name    = string
    code    = string # JS source code (read from file)
    publish = optional(bool, true)

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
