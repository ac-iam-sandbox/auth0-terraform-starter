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
