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

variable "region" {
  type = string
}

variable "environment" {
  type = string
}
