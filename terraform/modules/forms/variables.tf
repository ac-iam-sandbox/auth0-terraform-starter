variable "definitions" {
  type = any
}

variable "environment" {
  type = string
}

variable "flow_outputs" {
  type    = map(string)
  default = {}
}

variable "vault_connection_outputs" {
  type    = map(string)
  default = {}
}
