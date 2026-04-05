variable "definitions" {
  type = any
}

variable "forms_manifest" {
  description = "Forms definitions for resolving source_form file paths"
  type        = any
  default     = {}
}

variable "environment" {
  type = string
}

variable "vault_connection_outputs" {
  type    = map(string)
  default = {}
}
