variable "definitions" {
  type = any
}

variable "secrets" {
  type      = map(string)
  sensitive = true
}

variable "env_config" {
  type = any
}

variable "environment" {
  type = string
}

variable "form_ids" {
  description = "Map of form key to Auth0 form ID, from the forms module"
  type        = map(string)
  default     = {}
}

variable "action_module_outputs" {
  description = "Map of action module key to { id, version_id }, from the action_modules module"
  type = map(object({
    id         = string
    version_id = string
  }))
  default = {}
}
