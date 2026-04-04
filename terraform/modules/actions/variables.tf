variable "definitions" {
  type = any
}

variable "secrets" {
  type      = map(string)
  sensitive = true
}

variable "environment" {
  type = string
}

variable "action_module_outputs" {
  type    = map(object({ id = string, version_id = string }))
  default = {}
}
