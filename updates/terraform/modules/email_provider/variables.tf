variable "definition" {
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

variable "client_ids" {
  description = "Map of client key to Auth0 client_id, from the clients module"
  type        = map(string)
  default     = {}
}

variable "client_secrets" {
  description = "Map of client key to Auth0 client_secret — only for clients with expose_credentials: true"
  type        = map(string)
  sensitive   = true
  default     = {}
}
