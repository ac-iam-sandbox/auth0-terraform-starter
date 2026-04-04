variable "definitions" {
  type = any
}

variable "environment" {
  type = string
}

variable "vault_connection_outputs" {
  type    = map(string)
  default = {}
}
