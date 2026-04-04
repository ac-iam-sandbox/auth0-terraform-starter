variable "definitions" {
  type = any
}

variable "environment" {
  type = string
}

# tflint-ignore: terraform_unused_declarations
variable "flow_outputs" {
  type    = map(string)
  default = {}
}

# tflint-ignore: terraform_unused_declarations
variable "vault_connection_outputs" {
  type    = map(string)
  default = {}
}
