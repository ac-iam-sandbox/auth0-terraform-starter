variable "definitions" {
  type = any
}

# tflint-ignore: terraform_unused_declarations — will be used when flows add environment filtering
variable "environment" {
  type = string
}

variable "vault_connection_outputs" {
  type    = map(string)
  default = {}
}
