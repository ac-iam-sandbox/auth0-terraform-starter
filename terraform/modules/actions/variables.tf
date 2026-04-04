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

variable "action_module_outputs" {
  type    = map(object({ id = string, version_id = string }))
  default = {}
}
