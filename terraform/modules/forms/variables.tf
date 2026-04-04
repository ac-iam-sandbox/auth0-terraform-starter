variable "definitions" {
  type = any
}

variable "environment" {
  type = string
}

# tflint-ignore: terraform_unused_declarations — will be used when auth0_form resource is implemented
variable "flow_outputs" {
  type    = map(string)
  default = {}
}

# tflint-ignore: terraform_unused_declarations — will be used when auth0_form resource is implemented
variable "vault_connection_outputs" {
  type    = map(string)
  default = {}
}
