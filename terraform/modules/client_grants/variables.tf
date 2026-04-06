variable "definitions" {
  type = any
}

variable "environment" {
  type = string
}

variable "client_ids" {
  description = "Map of client manifest key to Auth0 client_id (from clients module)"
  type        = map(string)
}

variable "management_api_identifier" {
  description = "The tenant's Management API audience identifier (from data.auth0_tenant)"
  type        = string
}
